#!/usr/bin/env node
// Generates seatbee/Resources/SampleEvent.json — the bundled demo plan that
// powers the in-app sample event. Runs the *real* web solver against the
// generated data and writes the resulting 100% assignment back into the
// JSON, so the iOS "AI seat" button can play it back without ever calling
// /api/ai. Re-run any time the demo content needs refreshing.
//
//   node scripts/generate-sample-event.mjs
//
// Solver source: ../Seated/src/lib/solve.js (the production web algorithm).
// If you change demo content and the validation fails, tweak the parties /
// rules / table layout until the script reports overallPercent === 100.

import { generateSeating } from '../../Seated/src/lib/solve.js'
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = resolve(__dirname, '..')
const OUT_PATH = resolve(REPO_ROOT, 'seatbee/Resources/SampleEvent.json')

// ── Helpers ────────────────────────────────────────────────────────────────

const id = (prefix) => `${prefix}-${Math.random().toString(36).slice(2, 9)}`
let _counter = 0
const seqId = (prefix) => `${prefix}-${(++_counter).toString().padStart(3, '0')}`

// Diverse first + last name pools. Mixed cultural backgrounds so the
// sample looks like a real wedding guest list, not a stock template.
const FIRST_NAMES_BRIDE_SIDE = [
  'Sophie', 'Emma', 'Charlotte', 'Olivia', 'Mia', 'Hannah', 'Grace', 'Lily',
  'Maya', 'Priya', 'Aisha', 'Fatima', 'Zara', 'Leila', 'Yasmin', 'Noor',
  'Mei', 'Lin', 'Yuki', 'Hana', 'Sora', 'Nina', 'Anya', 'Tara',
  'Daniel', 'Marcus', 'Ethan', 'Jacob', 'Liam', 'Owen', 'Cole', 'Ryan',
  'Aarav', 'Rohan', 'Vikram', 'Arjun', 'Kabir', 'Devan', 'Ravi', 'Sai',
  'Carol', 'Susan', 'Linda', 'Patricia', 'Margaret', 'Barbara', 'Helen', 'Sandra',
  'Robert', 'James', 'William', 'David', 'Richard', 'Charles', 'Thomas', 'Frank',
]
const FIRST_NAMES_GROOM_SIDE = [
  'Adaeze', 'Chiamaka', 'Ngozi', 'Folake', 'Amara', 'Ifeoma', 'Zuri', 'Kehinde',
  'Sofia', 'Isabella', 'Camila', 'Valentina', 'Lucia', 'Elena', 'Carmen', 'Rosa',
  'Sarah', 'Rachel', 'Hannah', 'Leah', 'Naomi', 'Esther', 'Miriam', 'Tamar',
  'Chinedu', 'Tunde', 'Obinna', 'Kwame', 'Jelani', 'Idris', 'Femi', 'Bayo',
  'Diego', 'Mateo', 'Carlos', 'Javier', 'Andres', 'Pablo', 'Luis', 'Marco',
  'Aaron', 'Ezra', 'Asher', 'Eli', 'Noah', 'Levi', 'Jonah', 'Caleb',
  'Helen', 'Gloria', 'Beverly', 'Eleanor', 'Catherine', 'Rose', 'Ruth', 'Edith',
  'George', 'Henry', 'Walter', 'Edward', 'Albert', 'Frederick', 'Arthur', 'Ernest',
]

const LAST_NAMES_BRIDE_SIDE = [
  'Williams', 'Park', 'Park-Williams', 'Williams-Patel', 'Patel', 'Singh', 'Khan',
  'Tanaka', 'Liu', 'Chen', 'Nakamura',
]
const LAST_NAMES_GROOM_SIDE = [
  'Carter', 'Okonkwo', 'Carter-Okonkwo', 'Hernández', 'García', 'Goldberg',
  'Cohen', 'Adebayo', 'Diallo', 'Ramirez',
]

const MEALS = [
  'Beef Tenderloin',
  'Pan-Seared Salmon',
  'Vegetarian Risotto',
  'Vegan Tasting Plate',
  'Kids Chicken Fingers',
]

const DIETARY_TAGS = [
  'gluten-free', 'dairy-free', 'nut-allergy', 'shellfish-allergy', 'kosher', 'halal',
]

// Round-robin pickers so we don't get duplicate guests
function makeRotator(arr) {
  let i = 0
  const used = new Set()
  return () => {
    let attempts = 0
    while (attempts < arr.length * 2) {
      const v = arr[i % arr.length]
      i++
      if (!used.has(v) || used.size >= arr.length) {
        used.add(v)
        return v
      }
      attempts++
    }
    // Exhausted unique values — start re-using
    return arr[i++ % arr.length]
  }
}

// ── Party definitions ──────────────────────────────────────────────────────
// 132 total guests across 13 logical groups.

const PARTY_DEFS = [
  { id: 'p_bride_imm',  name: "Bride's family",            count: 8,  side: 'bride' },
  { id: 'p_groom_imm',  name: "Groom's family",            count: 8,  side: 'groom' },
  { id: 'p_bride_williams', name: "Bride's Williams family", count: 12, side: 'bride' },
  { id: 'p_bride_park', name: "Bride's Park family",        count: 8,  side: 'bride' },
  { id: 'p_groom_carter', name: "Groom's Carter family",    count: 12, side: 'groom' },
  { id: 'p_groom_okonkwo', name: "Groom's Okonkwo family",  count: 8,  side: 'groom' },
  { id: 'p_bride_college', name: "Bride's college friends", count: 12, side: 'bride' },
  { id: 'p_groom_college', name: "Groom's college friends", count: 12, side: 'groom' },
  { id: 'p_bride_work',  name: "Bride's coworkers",         count: 8,  side: 'bride' },
  { id: 'p_groom_work',  name: "Groom's coworkers",         count: 8,  side: 'groom' },
  { id: 'p_brooks_friends', name: "Brooks family friends",  count: 10, side: 'groom' },
  { id: 'p_carter_friends', name: "Carter family friends",  count: 12, side: 'bride' },
  { id: 'p_plus_ones',  name: 'Plus-ones & misc',           count: 14, side: 'both' },
]
const TOTAL = PARTY_DEFS.reduce((s, p) => s + p.count, 0)
if (TOTAL !== 132) {
  console.error(`Party total = ${TOTAL}, expected 132`)
  process.exit(1)
}

// ── Generate guests ────────────────────────────────────────────────────────

const brideFirst = makeRotator(FIRST_NAMES_BRIDE_SIDE)
const groomFirst = makeRotator(FIRST_NAMES_GROOM_SIDE)
const brideLast = makeRotator(LAST_NAMES_BRIDE_SIDE)
const groomLast = makeRotator(LAST_NAMES_GROOM_SIDE)

function pickName(side) {
  if (side === 'bride')      return [brideFirst(), brideLast()]
  else if (side === 'groom') return [groomFirst(), groomLast()]
  else return Math.random() < 0.5
    ? [brideFirst(), brideLast()]
    : [groomFirst(), groomLast()]
}

const guests = []
const guestsByParty = {}

// First, the couple (going to sweetheart). Names are anchors for the event.
const bride = {
  id: 'g_bride',
  firstName: 'Brooks', lastName: 'Williams',
  name: 'Brooks Williams', display: 'Brooks',
  side: 'none', vip: true, rsvp: 'yes',
  party: 'p_bride_imm',
  meal: 'Pan-Seared Salmon',
  categories: [], dietaryTags: [], plusOne: false,
  isBride: true,
}
const groom = {
  id: 'g_groom',
  firstName: 'Carter', lastName: 'Okonkwo',
  name: 'Carter Okonkwo', display: 'Carter',
  side: 'none', vip: true, rsvp: 'yes',
  party: 'p_groom_imm',
  meal: 'Beef Tenderloin',
  categories: [], dietaryTags: [], plusOne: false,
  isGroom: true,
}
guests.push(bride, groom)
guestsByParty['p_bride_imm'] = [bride]
guestsByParty['p_groom_imm'] = [groom]

// Wedding party members (10 people at head table)
// — bride parents 2, groom parents 2, MOH (bride's sister), 3 bridesmaids
//   (bride college friends), Best Man (groom's brother), 3 groomsmen
//   (groom college friends).
const weddingPartyIds = []

function addGuest(partyDef, opts = {}) {
  const [first, last] = opts.firstName
    ? [opts.firstName, opts.lastName]
    : pickName(partyDef.side)
  const g = {
    id: seqId('g'),
    firstName: first, lastName: last,
    name: `${first} ${last}`,
    display: first,
    // side is intentionally 'none' for the demo — see the solver-input
    // build site for the rationale (auto side_together rules can't hit
    // 100% on a sweetheart + head-table T-shape).
    side: 'none',
    vip: opts.vip || false,
    rsvp: opts.rsvp || 'yes',
    party: partyDef.id,
    meal: opts.meal || null,
    categories: [],
    dietaryTags: opts.dietaryTags || [],
    plusOne: opts.plusOne || false,
    isChild: opts.isChild || false,
  }
  guests.push(g)
  if (!guestsByParty[partyDef.id]) guestsByParty[partyDef.id] = []
  guestsByParty[partyDef.id].push(g)
  return g
}

// Bride's immediate family (8 total, bride already added → 7 more)
const PARTY_BRIDE_IMM = PARTY_DEFS[0]
const brideMom    = addGuest(PARTY_BRIDE_IMM, { firstName: 'Patricia', lastName: 'Williams', vip: true })
const brideDad    = addGuest(PARTY_BRIDE_IMM, { firstName: 'David',    lastName: 'Williams', vip: true })
const brideMOH    = addGuest(PARTY_BRIDE_IMM, { firstName: 'Charlotte', lastName: 'Williams', vip: true })  // sister, MOH
addGuest(PARTY_BRIDE_IMM, { firstName: 'Owen',  lastName: 'Williams' })  // brother
addGuest(PARTY_BRIDE_IMM, { firstName: 'Margaret', lastName: 'Williams' }) // grandmother
addGuest(PARTY_BRIDE_IMM, { firstName: 'James', lastName: 'Williams' }) // grandfather (divorced)
addGuest(PARTY_BRIDE_IMM, { firstName: 'Helen', lastName: 'Park' })    // grandmother on Park side

// Groom's immediate family (8 total, groom already added → 7 more)
const PARTY_GROOM_IMM = PARTY_DEFS[1]
const groomMom    = addGuest(PARTY_GROOM_IMM, { firstName: 'Adaeze',   lastName: 'Okonkwo', vip: true })
const groomDad    = addGuest(PARTY_GROOM_IMM, { firstName: 'Chinedu',  lastName: 'Okonkwo', vip: true })
const groomBM     = addGuest(PARTY_GROOM_IMM, { firstName: 'Tunde',    lastName: 'Okonkwo', vip: true })  // brother, Best Man
addGuest(PARTY_GROOM_IMM, { firstName: 'Ifeoma',  lastName: 'Okonkwo' })  // sister
addGuest(PARTY_GROOM_IMM, { firstName: 'Ngozi',   lastName: 'Okonkwo' })  // grandmother
addGuest(PARTY_GROOM_IMM, { firstName: 'Obinna',  lastName: 'Okonkwo' })  // uncle
addGuest(PARTY_GROOM_IMM, { firstName: 'Amara',   lastName: 'Carter' })   // grandmother on Carter side

// Bride's Williams extended (12)
for (let i = 0; i < PARTY_DEFS[2].count; i++) addGuest(PARTY_DEFS[2])
// Bride's Park extended (8)
for (let i = 0; i < PARTY_DEFS[3].count; i++) addGuest(PARTY_DEFS[3])
// Groom's Carter extended (12)
for (let i = 0; i < PARTY_DEFS[4].count; i++) addGuest(PARTY_DEFS[4])
// Groom's Okonkwo extended (8)
for (let i = 0; i < PARTY_DEFS[5].count; i++) addGuest(PARTY_DEFS[5])

// Bride's college friends (12) — first 3 are bridesmaids
const PARTY_BRIDE_COLLEGE = PARTY_DEFS[6]
const brideMaid1 = addGuest(PARTY_BRIDE_COLLEGE, { firstName: 'Maya', lastName: 'Patel', vip: true })
const brideMaid2 = addGuest(PARTY_BRIDE_COLLEGE, { firstName: 'Yuki', lastName: 'Tanaka', vip: true })
const brideMaid3 = addGuest(PARTY_BRIDE_COLLEGE, { firstName: 'Aisha', lastName: 'Khan', vip: true })
for (let i = 0; i < PARTY_BRIDE_COLLEGE.count - 3; i++) addGuest(PARTY_BRIDE_COLLEGE)

// Groom's college friends (12) — first 3 are groomsmen
const PARTY_GROOM_COLLEGE = PARTY_DEFS[7]
const groomMan1 = addGuest(PARTY_GROOM_COLLEGE, { firstName: 'Jelani', lastName: 'Adebayo', vip: true })
const groomMan2 = addGuest(PARTY_GROOM_COLLEGE, { firstName: 'Diego',  lastName: 'Hernández', vip: true })
const groomMan3 = addGuest(PARTY_GROOM_COLLEGE, { firstName: 'Aaron',  lastName: 'Goldberg', vip: true })
for (let i = 0; i < PARTY_GROOM_COLLEGE.count - 3; i++) addGuest(PARTY_GROOM_COLLEGE)

// Coworkers (8 + 8)
for (let i = 0; i < PARTY_DEFS[8].count; i++) addGuest(PARTY_DEFS[8])
for (let i = 0; i < PARTY_DEFS[9].count; i++) addGuest(PARTY_DEFS[9])

// Family friends (10 + 12)
for (let i = 0; i < PARTY_DEFS[10].count; i++) addGuest(PARTY_DEFS[10])
for (let i = 0; i < PARTY_DEFS[11].count; i++) addGuest(PARTY_DEFS[11])

// Plus-ones / misc (14) — sprinkle in a couple of children
const PARTY_PLUS_ONES = PARTY_DEFS[12]
addGuest(PARTY_PLUS_ONES, { firstName: 'Ezra',  lastName: 'Goldberg-Lin', isChild: true, meal: 'Kids Chicken Fingers' })
addGuest(PARTY_PLUS_ONES, { firstName: 'Lucia', lastName: 'Hernández',   isChild: true, meal: 'Kids Chicken Fingers' })
for (let i = 0; i < PARTY_PLUS_ONES.count - 2; i++) addGuest(PARTY_PLUS_ONES, { plusOne: true })

if (guests.length !== 132) {
  console.error(`Generated ${guests.length} guests, expected 132`)
  process.exit(1)
}

// ── Meal + dietary distribution ────────────────────────────────────────────
// Meals: Beef ~38%, Salmon ~30%, Vegetarian Risotto ~19%, Vegan ~5%, Kids ~8%

const mealTargets = {
  'Beef Tenderloin': 50,
  'Pan-Seared Salmon': 40,
  'Vegetarian Risotto': 25,
  'Vegan Tasting Plate': 7,
  'Kids Chicken Fingers': 10,
}
const mealCounts = Object.fromEntries(MEALS.map(m => [m, 0]))
for (const g of guests) if (g.meal) mealCounts[g.meal]++

// Fill the rest
let mealIdx = 0
for (const g of guests) {
  if (g.meal) continue
  // round-robin meals while respecting targets
  while (true) {
    const meal = MEALS[mealIdx % MEALS.length]
    mealIdx++
    if (mealCounts[meal] < mealTargets[meal]) {
      g.meal = meal
      mealCounts[meal]++
      break
    }
    if (mealIdx > MEALS.length * 200) {
      g.meal = 'Beef Tenderloin'  // fallback if targets are tight
      mealCounts['Beef Tenderloin']++
      break
    }
  }
}

// Dietary tags on ~12 guests
const dietaryAssignments = [
  { name: 'g-009', tag: 'gluten-free' },
  { name: 'g-014', tag: 'gluten-free' },
  { name: 'g-022', tag: 'dairy-free' },
  { name: 'g-031', tag: 'nut-allergy' },
  { name: 'g-040', tag: 'shellfish-allergy' },
  { name: 'g-055', tag: 'kosher' },
  { name: 'g-067', tag: 'halal' },
  { name: 'g-073', tag: 'gluten-free' },
  { name: 'g-088', tag: 'dairy-free' },
  { name: 'g-095', tag: 'nut-allergy' },
  { name: 'g-110', tag: 'kosher' },
  { name: 'g-122', tag: 'halal' },
]
for (const { name, tag } of dietaryAssignments) {
  const g = guests.find(x => x.id === name)
  if (g) g.dietaryTags = [tag]
}

// ── Tables (T-shape venue) ─────────────────────────────────────────────────
//
// Coordinates use the web's SCALE = 15 px / ft. Room is 80 ft × 60 ft.
// Sweetheart at top-center, head table just below, then 16 round tables
// in a 4×4 grid forming the stem of the T.

const ROOM_W = 1200  // 80 ft × 15
const ROOM_H = 900   // 60 ft × 15

const tables = []

// Sweetheart (heart-shaped, 2 seats), center top
const sweetheart = {
  id: 't_sweet',
  name: 'Sweetheart',
  type: 'sweetheart',
  seats: 2,
  x: ROOM_W / 2 - 50,
  y: 80,
  width: 100, height: 70,
  sweetShape: 'heart',
  color: '#C9A961',
  assignments: {},
}
tables.push(sweetheart)

// Head table (long rectangle, 10 seats, one-side seating)
const head = {
  id: 't_head',
  name: 'Head Table',
  type: 'head',
  seats: 10,
  x: ROOM_W / 2 - 200,
  y: 200,
  width: 400, height: 70,
  oneSide: true,
  color: '#C9A961',
  assignments: {},
}
tables.push(head)

// 4 columns × 4 rows of round tables = 16 tables, 8 seats each
const roundCols = [180, 460, 740, 1020]
const roundRows = [400, 540, 680, 820]
let roundIdx = 0
for (const y of roundRows) {
  for (const x of roundCols) {
    roundIdx++
    tables.push({
      id: `t_round_${roundIdx.toString().padStart(2, '0')}`,
      name: `Table ${roundIdx}`,
      type: 'round',
      seats: 8,
      x: x - 50,  // diameter / 2
      y: y - 50,
      diameter: 100,
      color: '#C9A961',
      assignments: {},
    })
  }
}

// ── Pre-assign sweetheart + head table via existingAssignments ─────────────

const headTableMembers = [
  brideMOH, brideMaid1, brideMaid2, brideMaid3, brideMom, brideDad,
  groomDad, groomMom, groomBM, groomMan1,
]
// Note: only 10 head-table seats, so groomMan2 + groomMan3 sit at a round
// table near the head. The rule we add later keeps them with the rest of
// the bridal-party-adjacent college friends.

const existingAssignments = {}
existingAssignments[bride.id] = head.id   // for solver: sweetheart counted as head-adj
existingAssignments[groom.id] = sweetheart.id
// Actually pin them properly:
existingAssignments[bride.id] = sweetheart.id
existingAssignments[groom.id] = sweetheart.id
for (const g of headTableMembers) {
  existingAssignments[g.id] = head.id
}

// ── Rules (10) ────────────────────────────────────────────────────────────

const rules = []
function ruleMustTogether(name, partyId, guestIds) {
  rules.push({
    id: seqId('r'),
    type: 'must_together',
    guests: guestIds,
    weight: 10,
    hard: true,
    enabled: true,
    desc: name,
    partyId,
  })
}
function ruleMustNot(name, a, b) {
  rules.push({
    id: seqId('r'),
    type: 'must_not',
    guests: [a, b],
    weight: 10,
    hard: true,
    enabled: true,
    desc: name,
  })
}

// 6 must_together rules — only on parties that fit at one table (≤8)
// excluding members already pinned to head/sweetheart.
function partyRoundTableMembers(partyId) {
  return guestsByParty[partyId]
    .filter(g => !existingAssignments[g.id])
    .map(g => g.id)
}

// 1. Bride's immediate family (round-table remainder ≤ 4)
ruleMustTogether("Bride's family at one table", 'p_bride_imm',
  partyRoundTableMembers('p_bride_imm'))
// 2. Groom's immediate family (round-table remainder ≤ 4)
ruleMustTogether("Groom's family at one table", 'p_groom_imm',
  partyRoundTableMembers('p_groom_imm'))
// 3. Bride's coworkers (8) — fits exactly at one 8-seat round
ruleMustTogether("Bride's coworkers together", 'p_bride_work',
  partyRoundTableMembers('p_bride_work'))
// 4. Groom's coworkers (8) — fits exactly
ruleMustTogether("Groom's coworkers together", 'p_groom_work',
  partyRoundTableMembers('p_groom_work'))
// 5. Bride's Park family (8) — fits exactly
ruleMustTogether("Park family together", 'p_bride_park',
  partyRoundTableMembers('p_bride_park'))
// 6. Groom's Okonkwo family (8) — fits exactly
ruleMustTogether("Okonkwo family together", 'p_groom_okonkwo',
  partyRoundTableMembers('p_groom_okonkwo'))

// 4 must_not rules — pick guests across DIFFERENT parties so none of these
// can collide with a must_together (which is always within a single party).
//
// Bride's grandfather (Williams) ↔ Brooks family friend: family rift across
// the bride/groom split, neither in a party with a must_together rule.
const williamsExt = guestsByParty['p_bride_williams']
const brooksFriends = guestsByParty['p_brooks_friends']
ruleMustNot('Estranged in-laws keep apart', williamsExt[0].id, brooksFriends[0].id)

// Carter cousin (extended) ↔ Carter family friend: feud between branches,
// different parties.
const carterClan = guestsByParty['p_groom_carter']
const carterFriends = guestsByParty['p_carter_friends']
ruleMustNot('Old Carter feud apart', carterClan[0].id, carterFriends[0].id)

// Plus-one ↔ Brooks family friend (different person): old workplace drama
const plusOnes = guestsByParty['p_plus_ones']
const plusOneAdult = plusOnes.find(g => !g.isChild)
ruleMustNot('Old workplace drama apart', brooksFriends[1].id, plusOneAdult.id)

// Bride coworker ↔ Groom coworker: ex-colleagues from a different company
const brideWork = guestsByParty['p_bride_work']
const groomWork = guestsByParty['p_groom_work']
ruleMustNot('Ex-colleagues keep apart', brideWork[0].id, groomWork[0].id)

if (rules.length !== 10) {
  console.error(`Generated ${rules.length} rules, expected 10`)
  process.exit(1)
}

// ── Categories + Parties (web-shape passthrough) ──────────────────────────

const categories = []  // sample doesn't need custom categories — parties suffice
const parties = PARTY_DEFS.map(p => ({
  id: p.id,
  name: p.name,
  guestIds: guestsByParty[p.id]?.map(g => g.id) || [],
}))

// ── Run the solver ────────────────────────────────────────────────────────

console.log(`Running solver: ${guests.length} guests, ${tables.length} tables, ${rules.length} rules…`)

// Build solver-shaped guests (it expects {id, name, party, ...} — see solve.js).
//
// IMPORTANT: side is intentionally "none" for everyone. The solver auto-
// synthesizes a `side_together` soft rule for any guest with side === 'bride'
// or 'groom', and our T-shape (sweetheart + head table) mixes both sides
// at the front by design. That makes those auto-rules structurally
// impossible to fully satisfy. Suppressing them gets us a clean 100%.
// Parties, meals, dietary, rules, VIP — everything else is preserved.
const solverGuests = guests.map(g => ({
  id: g.id,
  name: g.name,
  party: g.party,
  side: 'none',
  vip: g.vip,
  rsvp: g.rsvp,
  meal: g.meal,
  dietaryTags: g.dietaryTags,
  isChild: g.isChild,
  categories: g.categories,
}))

// Note: `parties` are NOT passed as `units` — units in the solver are
// atomic (must-stay-together no matter what), which would override the
// must_not rules and force 12-person parties into 8-seat tables. Parties
// here are just a passthrough display grouping; cohesion is driven by
// the explicit must_together rules above.
const solverResult = generateSeating(
  tables.map(t => ({ ...t })),  // shallow copy
  solverGuests,
  rules,
  categories,
  existingAssignments,
  42,  // seed
  [],   // units (intentionally empty — see note above)
  [],   // groups
  [],   // objects
  null  // llmStrategy
)

const sc = solverResult.scorecard
console.log(`Score: ${sc.overallPercent}% (${sc.overallLabel})`)
console.log(`Rules: ${sc.totalSatisfied}/${sc.totalRules} satisfied`)
console.log(`Hard: ${sc.hardConstraints.satisfied}/${sc.hardConstraints.total}, ` +
            `Soft: ${sc.softPreferences.satisfied}/${sc.softPreferences.total}`)
console.log(`Assignments: ${Object.keys(solverResult.assignments).length} / ${guests.length} guests placed`)
if (solverResult.fallback) {
  console.error('⚠️  Solver fell back to round-robin — pre-baked result is not a real solve.')
}

if (sc.overallPercent < 100) {
  console.error('❌ Score below 100%. Inspect rules:')
  for (const r of [...sc.hardConstraints.rules, ...sc.softPreferences.rules]) {
    console.error(`  [${r.status}] ${r.type}: ${r.desc || ''} ` +
                  `(guests: ${(r.guests || []).slice(0, 3).join(', ')}…)`)
  }
  process.exit(1)
}

// ── Build the output JSON ──────────────────────────────────────────────────
//
// Matches the iOS PlanDataDTO shape so SampleEventService can hydrate it
// directly into a SeatingPlan without round-tripping through Supabase.

const today = new Date()
const eventDate = new Date(today.getFullYear() + 1, 5, 14)  // June 14 next year (find Saturday)
while (eventDate.getDay() !== 6) eventDate.setDate(eventDate.getDate() + 1)

// Embed the pre-baked assignments into each table's `assignments` map.
// iOS reads assignments at the table level (SeatTable.assignments).
const assignmentsByTable = {}
const seatOrders = solverResult.seatOrders || {}
for (const [guestId, tableId] of Object.entries(solverResult.assignments)) {
  if (!assignmentsByTable[tableId]) assignmentsByTable[tableId] = []
  assignmentsByTable[tableId].push(guestId)
}
// Distribute seat indices 0..(seats-1) per table, honoring seatOrders if present
for (const t of tables) {
  const ids = assignmentsByTable[t.id] || []
  // Sort by seatOrder if available, else alphabetically by name
  const sorted = ids.slice().sort((a, b) => {
    const oa = seatOrders[a] ?? 999
    const ob = seatOrders[b] ?? 999
    if (oa !== ob) return oa - ob
    const ga = guests.find(g => g.id === a)
    const gb = guests.find(g => g.id === b)
    return (ga?.name || '').localeCompare(gb?.name || '')
  })
  sorted.forEach((gid, i) => { t.assignments[gid] = i })
}

const output = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  solverScore: sc.overallPercent,
  plan: {
    id: 'demo-sample-event',
    name: 'Carter & Brooks Wedding',
    eventDate: eventDate.toISOString().slice(0, 10),
    venue: 'The Magnolia Estate',
    eventType: 'wedding',
    isDemo: true,
    roomWidth: ROOM_W,
    roomHeight: ROOM_H,
    roomShape: 't',
    measurementUnit: 'imperial',
    hasSweetheartTable: true,
    coupleType: 'bride_groom',
    tables,
    guests,
    rules,
    objects: [],
    categories,
    parties,
  },
  // Pre-baked AI playback — what gets applied when the user taps the AI
  // button on the sample plan. Identical shape to the solver's output so
  // the playback path can swap it in without translation.
  preBakedAI: {
    assignments: solverResult.assignments,
    seatOrders: solverResult.seatOrders,
    score: solverResult.score,
    scorecard: solverResult.scorecard,
  },
}

mkdirSync(dirname(OUT_PATH), { recursive: true })
writeFileSync(OUT_PATH, JSON.stringify(output, null, 2))
console.log(`\n✅ Wrote ${OUT_PATH}`)
console.log(`   ${guests.length} guests · ${tables.length} tables · ${rules.length} rules`)
console.log(`   Solver: ${sc.overallPercent}% (${sc.overallLabel})`)
console.log(`   Meal counts:`, mealCounts)
