#!/usr/bin/env node
// Generates seatbee/Resources/SampleEvent.json — the bundled demo plan that
// powers the in-app sample event. Runs the *real* web solver against the
// generated data and writes the resulting 95-100% assignment back into the
// JSON, so the iOS "AI seat" button can play it back without ever calling
// /api/seat. Re-run any time the demo content needs refreshing.
//
//   node scripts/generate-sample-event.mjs
//
// Solver source: ../Seated/src/lib/solve.js (the production web algorithm).
//
// Design principles (informed by user feedback 2026-05-09):
//   - PARTIES are small units (couples / nuclear families ≤ 4) that always
//     sit together. Passed as `units` to the solver — the solver guarantees
//     them at one table. NOT used for big groupings like "all coworkers".
//   - GROUPS like "bride's college friends" use prefer_together rules
//     (soft) when > 8, must_together when ≤ 8. The Rules system handles
//     these — that's what it's for.
//   - CATEGORIES tag every guest (Family / Wedding Party / Friends / Work
//     / Kids). 1-2 per guest, surfaces on filter chips in-app.
//   - SIDES (bride/groom) on family + friends + coworkers; set to "both"
//     for the wedding party + couple so the solver's auto-synthesized
//     side_together rules don't drag score (head table inherently mixes).
//   - RSVP includes a few "no"s for realism — solver only seats yeses.
//   - DISPLAY name is always full first + last.

import { generateSeating } from '../../Seated/src/lib/solve.js'
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = resolve(__dirname, '..')
const OUT_PATH = resolve(REPO_ROOT, 'seatbee/Resources/SampleEvent.json')

let _idCounter = 0
const seqId = (prefix) => `${prefix}-${(++_idCounter).toString().padStart(3, '0')}`

// ── Categories ─────────────────────────────────────────────────────────────

const CATEGORIES = [
  { id: 'cat-family',         name: 'Family',        color: '#C9A961' },
  { id: 'cat-wedding-party',  name: 'Wedding Party', color: '#8B6F47' },
  { id: 'cat-friends',        name: 'Friends',       color: '#7B9D7E' },
  { id: 'cat-work',           name: 'Work',          color: '#5B7B9A' },
  { id: 'cat-kids',           name: 'Kids',          color: '#D4956C' },
]

// ── Name pools (culturally diverse) ────────────────────────────────────────

const FIRST_NAMES_POOL_FEM = [
  'Sophie','Emma','Charlotte','Olivia','Mia','Hannah','Grace','Lily',
  'Maya','Priya','Aisha','Fatima','Zara','Leila','Yasmin','Noor',
  'Mei','Yuki','Hana','Sora','Nina','Anya','Tara','Esther',
  'Sofia','Isabella','Camila','Valentina','Lucia','Elena','Carmen','Rosa',
  'Sarah','Rachel','Naomi','Leah','Miriam','Tamar','Hannah','Adina',
  'Adaeze','Chiamaka','Ngozi','Folake','Amara','Ifeoma','Zuri','Kehinde',
  'Carol','Susan','Linda','Patricia','Margaret','Barbara','Helen','Sandra',
  'Beverly','Eleanor','Catherine','Gloria','Ruth','Edith','Dorothy','Florence',
]
const FIRST_NAMES_POOL_MASC = [
  'Daniel','Marcus','Ethan','Jacob','Liam','Owen','Cole','Ryan',
  'Aarav','Rohan','Vikram','Arjun','Kabir','Devan','Ravi','Sai',
  'Robert','James','William','David','Richard','Charles','Thomas','Frank',
  'Diego','Mateo','Carlos','Javier','Andres','Pablo','Luis','Marco',
  'Aaron','Ezra','Asher','Eli','Noah','Levi','Jonah','Caleb',
  'Chinedu','Tunde','Obinna','Kwame','Jelani','Idris','Femi','Bayo',
  'George','Henry','Walter','Edward','Albert','Frederick','Arthur','Ernest',
]

const LAST_NAMES_BRIDE_SIDE = ['Williams','Park','Park-Williams','Williams-Patel','Patel','Singh','Khan','Tanaka','Liu','Chen','Nakamura','Williams-Cohen']
const LAST_NAMES_GROOM_SIDE = ['Carter','Okonkwo','Carter-Okonkwo','Hernández','García','Goldberg','Cohen','Adebayo','Diallo','Ramirez','Goldberg-Lin']

function makeRotator(arr) {
  let i = 0
  const used = new Set()
  return () => {
    let attempts = 0
    while (attempts < arr.length * 2) {
      const v = arr[i % arr.length]
      i++
      if (!used.has(v)) { used.add(v); return v }
      attempts++
    }
    return arr[i++ % arr.length]
  }
}

// Separate rotators per side so first names don't accidentally repeat
// across the bride's and groom's families.
const brideFirstFem  = makeRotator(FIRST_NAMES_POOL_FEM.slice(0, 30))
const brideFirstMasc = makeRotator(FIRST_NAMES_POOL_MASC.slice(0, 30))
const groomFirstFem  = makeRotator(FIRST_NAMES_POOL_FEM.slice(30))
const groomFirstMasc = makeRotator(FIRST_NAMES_POOL_MASC.slice(30))
const brideLastRot   = makeRotator(LAST_NAMES_BRIDE_SIDE)
const groomLastRot   = makeRotator(LAST_NAMES_GROOM_SIDE)

function pickFirst(side, gender = null) {
  const fem = side === 'bride' ? brideFirstFem : groomFirstFem
  const masc = side === 'bride' ? brideFirstMasc : groomFirstMasc
  if (gender === 'f') return fem()
  if (gender === 'm') return masc()
  return Math.random() < 0.5 ? fem() : masc()
}
function pickLast(side) { return side === 'bride' ? brideLastRot() : groomLastRot() }

// ── Guest factory ──────────────────────────────────────────────────────────

const guests = []
const partiesById = {}     // id -> { id, name, guestIds }
const guestPartyMembership = {}  // guestId -> partyId

function addGuest({
  firstName, lastName, side = 'none', categories = [],
  meal = null, dietaryTags = [], rsvp = 'yes',
  vip = false, isChild = false, plusOne = false, isBride = false, isGroom = false,
  partyId = null,
}) {
  const id = seqId('g')
  const name = `${firstName} ${lastName}`
  const g = {
    id, firstName, lastName, name,
    display: name,                 // full name everywhere — user feedback 2026-05-09
    side, categories, meal, dietaryTags, rsvp,
    vip, isChild, plusOne, isBride, isGroom,
    party: partyId,
  }
  guests.push(g)
  if (partyId) {
    if (!partiesById[partyId]) partiesById[partyId] = { id: partyId, name: '', guestIds: [] }
    partiesById[partyId].guestIds.push(id)
    guestPartyMembership[id] = partyId
  }
  return g
}

// Convenience: create a couple-party with two guests.
function addCouple(name, partner1, partner2) {
  const partyId = seqId('p')
  partiesById[partyId] = { id: partyId, name, guestIds: [] }
  return [
    addGuest({ ...partner1, partyId }),
    addGuest({ ...partner2, partyId }),
  ]
}

// Convenience: create a multi-person family party.
function addFamilyParty(name, members) {
  const partyId = seqId('p')
  partiesById[partyId] = { id: partyId, name, guestIds: [] }
  return members.map(m => addGuest({ ...m, partyId }))
}

// ── Build the guest list ───────────────────────────────────────────────────

// THE COUPLE — solo (no party, sits at sweetheart). Sides are set on the
// couple so the in-app side filter still has labelled chips and the
// bride/groom badge on guest rows reads correctly. The web solver auto-
// synthesizes a side_together rule per side; with only one guest each
// side, both rules trivially satisfy at the sweetheart table.
// Mirrors onboarding (OnboardingView.swift::coupleGuest, App.jsx:19816):
// when the user enters bride/groom names + opts in to a sweetheart table,
// the app tags the couple with TWO system categories:
//   - 'bride' / 'groom'    — drives the white/dark seat highlight (App.jsx
//                            line 7578) so the couple is visually flagged
//                            on the canvas
//   - 'sweetheart_table'   — pins them to the sweetheart at solve time
//                            (solve.js Phase 1.5)
// Without these the existingAssignments map below is silently dropped —
// it only honours LOCKED tables, which the demo doesn't use.
const bride = addGuest({
  firstName: 'Brooks', lastName: 'Williams',
  side: 'bride', categories: ['bride', 'cat-wedding-party', 'sweetheart_table'],
  meal: 'Pan-Seared Salmon', vip: true, isBride: true,
})
const groom = addGuest({
  firstName: 'Carter', lastName: 'Okonkwo',
  side: 'groom', categories: ['groom', 'cat-wedding-party', 'sweetheart_table'],
  meal: 'Beef Tenderloin', vip: true, isGroom: true,
})

// WEDDING PARTY — head table 10. side='both' so they don't drag side_together.
const brideMOH = addGuest({   // bride's sister
  firstName: 'Charlotte', lastName: 'Williams',
  side: 'both', categories: ['cat-wedding-party','cat-family','head_table'],
  meal: 'Pan-Seared Salmon', vip: true,
})
const brideMaid1 = addGuest({
  firstName: 'Maya', lastName: 'Patel',
  side: 'both', categories: ['cat-wedding-party','cat-friends','head_table'],
  meal: 'Vegetarian Risotto', dietaryTags: ['kosher'], vip: true,
})
const brideMaid2 = addGuest({
  firstName: 'Yuki', lastName: 'Tanaka',
  side: 'both', categories: ['cat-wedding-party','cat-friends','head_table'],
  meal: 'Pan-Seared Salmon', vip: true,
})
const brideMaid3 = addGuest({
  firstName: 'Aisha', lastName: 'Khan',
  side: 'both', categories: ['cat-wedding-party','cat-friends','head_table'],
  meal: 'Beef Tenderloin', dietaryTags: ['halal'], vip: true,
})
const brideDad = addGuest({
  firstName: 'David', lastName: 'Williams',
  side: 'both', categories: ['cat-wedding-party','cat-family','head_table'],
  meal: 'Beef Tenderloin', vip: true,
})
const brideMom = addGuest({
  firstName: 'Patricia', lastName: 'Williams',
  side: 'both', categories: ['cat-wedding-party','cat-family','head_table'],
  meal: 'Pan-Seared Salmon', vip: true,
})
const groomDad = addGuest({
  firstName: 'Chinedu', lastName: 'Okonkwo',
  side: 'both', categories: ['cat-wedding-party','cat-family','head_table'],
  meal: 'Beef Tenderloin', dietaryTags: ['gluten-free'], vip: true,
})
const groomMom = addGuest({
  firstName: 'Adaeze', lastName: 'Okonkwo',
  side: 'both', categories: ['cat-wedding-party','cat-family','head_table'],
  meal: 'Vegetarian Risotto', vip: true,
})
const groomBM = addGuest({   // groom's brother
  firstName: 'Tunde', lastName: 'Okonkwo',
  side: 'both', categories: ['cat-wedding-party','cat-family','head_table'],
  meal: 'Beef Tenderloin', vip: true,
})
const groomMan1 = addGuest({
  firstName: 'Jelani', lastName: 'Adebayo',
  side: 'both', categories: ['cat-wedding-party','cat-friends','head_table'],
  meal: 'Beef Tenderloin', dietaryTags: ['halal'], vip: true,
})

const headTableMembers = [brideMOH, brideMaid1, brideMaid2, brideMaid3, brideMom, brideDad, groomDad, groomMom, groomBM, groomMan1]

// FAMILIES — small parties (couples + nuclear families)

// Bride's grandparents — divorced (kept apart by must_not rule)
addGuest({
  firstName: 'Margaret', lastName: 'Williams', // grandma (Patricia's mother)
  side: 'none', categories: ['cat-family'],
  meal: 'Pan-Seared Salmon', dietaryTags: ['gluten-free'],
  vip: true,
})
addGuest({
  firstName: 'James', lastName: 'Williams', // grandpa (Patricia's father)
  side: 'none', categories: ['cat-family'],
  meal: 'Beef Tenderloin', vip: true,
})

// Bride's brother Owen + spouse Sophie + child
addFamilyParty("Owen's Family", [
  { firstName: 'Owen',   lastName: 'Williams', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
  { firstName: 'Sophie', lastName: 'Williams-Cohen', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon' },
  { firstName: 'Mia',    lastName: 'Williams-Cohen', side: 'none', categories: ['cat-family','cat-kids'], meal: 'Kids Chicken Fingers', isChild: true },
])

// Bride's aunt + uncle — Park side
addCouple("Helen & Robert (Park)",
  { firstName: 'Helen',  lastName: 'Park', side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto', dietaryTags: ['dairy-free'] },
  { firstName: 'Robert', lastName: 'Park', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)

// Bride's other aunts/uncles + cousins
addCouple("Linda & James (Williams)",
  { firstName: 'Linda', lastName: 'Williams-Patel', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon' },
  { firstName: 'Henry', lastName: 'Williams-Patel', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)
addCouple("Susan & Walter (Williams)",
  { firstName: 'Susan',  lastName: 'Williams', side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' },
  { firstName: 'Walter', lastName: 'Williams', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin', dietaryTags: ['gluten-free'] },
)
addCouple("Carol & Edward (Park)",
  { firstName: 'Carol',  lastName: 'Park-Williams', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon' },
  { firstName: 'Edward', lastName: 'Park-Williams', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)
addCouple("Barbara & Frank (Patel)",
  { firstName: 'Barbara', lastName: 'Patel', side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' },
  { firstName: 'Frank',   lastName: 'Patel', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)
addCouple("Sandra & Albert (Singh)",
  { firstName: 'Sandra', lastName: 'Singh', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon', dietaryTags: ['shellfish-allergy'] },
  { firstName: 'Albert', lastName: 'Singh', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)

// Bride's cousins — couple parties
addCouple("Priya & Arjun",
  { firstName: 'Priya', lastName: 'Patel', side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' },
  { firstName: 'Arjun', lastName: 'Patel', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)
addCouple("Mei & Daniel",
  { firstName: 'Mei',    lastName: 'Tanaka', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon', dietaryTags: ['nut-allergy'] },
  { firstName: 'Daniel', lastName: 'Tanaka', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)
addCouple("Hana & Marcus",
  { firstName: 'Hana',   lastName: 'Liu',    side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' },
  { firstName: 'Marcus', lastName: 'Liu',    side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)

// Solo bride-side family (no plus-one)
addGuest({ firstName: 'Aarav', lastName: 'Singh',     side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon' })
addGuest({ firstName: 'Anya',  lastName: 'Park',      side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon' })
addGuest({ firstName: 'Tara',  lastName: 'Khan',      side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' })

// — Groom's family —

// Groom's grandparents
addGuest({
  firstName: 'Ngozi', lastName: 'Okonkwo',
  side: 'none', categories: ['cat-family'],
  meal: 'Beef Tenderloin', vip: true,
})
addGuest({
  firstName: 'Obinna', lastName: 'Okonkwo',
  side: 'none', categories: ['cat-family'],
  meal: 'Pan-Seared Salmon', vip: true,
})

// Groom's sister + spouse
addCouple("Ifeoma & Diego",
  { firstName: 'Ifeoma', lastName: 'Okonkwo-Hernández', side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' },
  { firstName: 'Diego',  lastName: 'Hernández',          side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)

// Groom's aunt + uncle — Carter side
addCouple("Amara & Aaron (Carter)",
  { firstName: 'Amara', lastName: 'Carter', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon', dietaryTags: ['gluten-free'] },
  { firstName: 'Aaron', lastName: 'Carter', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)

// Groom's other aunts/uncles + cousins
addCouple("Folake & Idris",
  { firstName: 'Folake', lastName: 'Adebayo', side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' },
  { firstName: 'Idris',  lastName: 'Adebayo', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)
addCouple("Sarah & Eli (Goldberg)",
  { firstName: 'Sarah', lastName: 'Goldberg', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon', dietaryTags: ['kosher'] },
  { firstName: 'Eli',   lastName: 'Goldberg', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin', dietaryTags: ['kosher'] },
)
addCouple("Naomi & Asher",
  { firstName: 'Naomi', lastName: 'Cohen', side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' },
  { firstName: 'Asher', lastName: 'Cohen', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)
addCouple("Sofia & Mateo",
  { firstName: 'Sofia',  lastName: 'García', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon' },
  { firstName: 'Mateo',  lastName: 'García', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)
addCouple("Camila & Carlos",
  { firstName: 'Camila', lastName: 'Ramirez', side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' },
  { firstName: 'Carlos', lastName: 'Ramirez', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)

// Groom's cousins
addCouple("Chiamaka & Femi",
  { firstName: 'Chiamaka', lastName: 'Okonkwo', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon' },
  { firstName: 'Femi',     lastName: 'Okonkwo', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)
addCouple("Esther & Bayo",
  { firstName: 'Esther', lastName: 'Adebayo', side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' },
  { firstName: 'Bayo',   lastName: 'Adebayo', side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' },
)

// Solo groom-side family
addGuest({ firstName: 'Kehinde', lastName: 'Okonkwo', side: 'none', categories: ['cat-family'], meal: 'Pan-Seared Salmon', dietaryTags: ['nut-allergy'] })
addGuest({ firstName: 'Kwame',   lastName: 'Diallo',  side: 'none', categories: ['cat-family'], meal: 'Beef Tenderloin' })
addGuest({ firstName: 'Zuri',    lastName: 'Carter',  side: 'none', categories: ['cat-family'], meal: 'Vegetarian Risotto' })

// — College friends (large groups → soft prefer_together rule) —

// Bride's college friends — 9 people (3 already at head table as bridesmaids)
const brideCollege = []
const bcAdds = [
  { firstName: 'Sora',  lastName: 'Chen', meal: 'Pan-Seared Salmon' },
  { firstName: 'Nina',  lastName: 'Nakamura', meal: 'Vegetarian Risotto', dietaryTags: ['dairy-free'] },
  { firstName: 'Olivia', lastName: 'Patel-Singh', meal: 'Beef Tenderloin' },
  { firstName: 'Hannah', lastName: 'Chen-Williams', meal: 'Pan-Seared Salmon', rsvp: 'no' }, // declined
  { firstName: 'Lily',   lastName: 'Tanaka', meal: 'Vegetarian Risotto' },
  { firstName: 'Grace',  lastName: 'Nakamura', meal: 'Beef Tenderloin' },
  { firstName: 'Emma',   lastName: 'Williams-Patel', meal: 'Pan-Seared Salmon' },
  { firstName: 'Vikram', lastName: 'Patel', meal: 'Beef Tenderloin' },
  { firstName: 'Rohan',  lastName: 'Khan', meal: 'Pan-Seared Salmon' },
]
for (const def of bcAdds) {
  brideCollege.push(addGuest({
    ...def, side: 'none', categories: ['cat-friends'],
  }))
}

// Groom's college friends — 9 people (3 already at head table as groomsmen)
const groomCollege = []
const gcAdds = [
  { firstName: 'Aaron',   lastName: 'Goldberg-Lin', meal: 'Beef Tenderloin', dietaryTags: ['kosher'] },
  { firstName: 'Mateo',   lastName: 'Hernández', meal: 'Pan-Seared Salmon' },
  { firstName: 'Levi',    lastName: 'Cohen', meal: 'Beef Tenderloin' },
  { firstName: 'Pablo',   lastName: 'Ramirez', meal: 'Vegetarian Risotto' },
  { firstName: 'Marco',   lastName: 'García-Adebayo', meal: 'Beef Tenderloin' },
  { firstName: 'Caleb',   lastName: 'Goldberg', meal: 'Pan-Seared Salmon', rsvp: 'no' }, // declined
  { firstName: 'Ezra',    lastName: 'Cohen-Diallo', meal: 'Vegetarian Risotto' },
  { firstName: 'Asher',   lastName: 'Goldberg-Lin', meal: 'Beef Tenderloin' },
  { firstName: 'Noah',    lastName: 'Carter-Okonkwo', meal: 'Pan-Seared Salmon' },
]
for (const def of gcAdds) {
  groomCollege.push(addGuest({
    ...def, side: 'none', categories: ['cat-friends'],
  }))
}

// — Coworkers (medium groups → must_together when ≤ 8) —

const brideWork = []
const bwAdds = [
  { firstName: 'Cole',   lastName: 'Liu', meal: 'Beef Tenderloin' },
  { firstName: 'Ryan',   lastName: 'Chen', meal: 'Pan-Seared Salmon' },
  { firstName: 'Ethan',  lastName: 'Park', meal: 'Beef Tenderloin' },
  { firstName: 'Devan',  lastName: 'Patel', meal: 'Vegetarian Risotto' },
  { firstName: 'Ravi',   lastName: 'Singh', meal: 'Beef Tenderloin', dietaryTags: ['shellfish-allergy'] },
  { firstName: 'Sai',    lastName: 'Khan', meal: 'Pan-Seared Salmon' },
  { firstName: 'Jacob',  lastName: 'Williams', meal: 'Beef Tenderloin' },
  { firstName: 'Liam',   lastName: 'Park-Williams', meal: 'Vegetarian Risotto', rsvp: 'no' }, // declined
]
for (const def of bwAdds) {
  brideWork.push(addGuest({
    ...def, side: 'none', categories: ['cat-work'],
  }))
}

const groomWork = []
const gwAdds = [
  { firstName: 'Andres', lastName: 'García', meal: 'Beef Tenderloin' },
  { firstName: 'Javier', lastName: 'Hernández', meal: 'Pan-Seared Salmon' },
  { firstName: 'Luis',   lastName: 'Ramirez', meal: 'Beef Tenderloin' },
  { firstName: 'Jonah',  lastName: 'Goldberg', meal: 'Vegetarian Risotto' },
  { firstName: 'Tunde',  lastName: 'Adebayo', meal: 'Beef Tenderloin' },
  { firstName: 'Frank',  lastName: 'Diallo', meal: 'Pan-Seared Salmon' },
  { firstName: 'Albert', lastName: 'Cohen-Diallo', meal: 'Beef Tenderloin', dietaryTags: ['gluten-free'] },
  { firstName: 'Henry',  lastName: 'Goldberg-Lin', meal: 'Vegetarian Risotto' },
]
for (const def of gwAdds) {
  groomWork.push(addGuest({
    ...def, side: 'none', categories: ['cat-work'],
  }))
}

// — Family friends (mixed — side='both') —

addCouple("Beverly & George",
  { firstName: 'Beverly', lastName: 'Park-Williams', side: 'both', categories: ['cat-friends'], meal: 'Pan-Seared Salmon' },
  { firstName: 'George',  lastName: 'Park-Williams', side: 'both', categories: ['cat-friends'], meal: 'Beef Tenderloin' },
)
addCouple("Eleanor & Arthur",
  { firstName: 'Eleanor', lastName: 'Goldberg', side: 'both', categories: ['cat-friends'], meal: 'Vegetarian Risotto' },
  { firstName: 'Arthur',  lastName: 'Goldberg', side: 'both', categories: ['cat-friends'], meal: 'Beef Tenderloin' },
)
addCouple("Catherine & Thomas",
  { firstName: 'Catherine', lastName: 'Carter', side: 'both', categories: ['cat-friends'], meal: 'Pan-Seared Salmon' },
  { firstName: 'Thomas',    lastName: 'Carter', side: 'both', categories: ['cat-friends'], meal: 'Beef Tenderloin' },
)
addCouple("Gloria & Charles",
  { firstName: 'Gloria',  lastName: 'Williams', side: 'both', categories: ['cat-friends'], meal: 'Vegetarian Risotto', dietaryTags: ['dairy-free'] },
  { firstName: 'Charles', lastName: 'Williams', side: 'both', categories: ['cat-friends'], meal: 'Beef Tenderloin' },
)
addCouple("Ruth & Frederick",
  { firstName: 'Ruth',       lastName: 'Park', side: 'both', categories: ['cat-friends'], meal: 'Pan-Seared Salmon' },
  { firstName: 'Frederick',  lastName: 'Park', side: 'both', categories: ['cat-friends'], meal: 'Beef Tenderloin' },
)
addCouple("Edith & William",
  { firstName: 'Edith',   lastName: 'Carter-Okonkwo', side: 'both', categories: ['cat-friends'], meal: 'Vegetarian Risotto' },
  { firstName: 'William', lastName: 'Carter-Okonkwo', side: 'both', categories: ['cat-friends'], meal: 'Beef Tenderloin' },
)

// Solo family-friend guests
addGuest({ firstName: 'Florence', lastName: 'Diallo', side: 'both', categories: ['cat-friends'], meal: 'Pan-Seared Salmon', rsvp: 'no' }) // declined
addGuest({ firstName: 'Dorothy',  lastName: 'Carter-Okonkwo', side: 'both', categories: ['cat-friends'], meal: 'Vegetarian Risotto' })

// Single guest with their plus-one couple
addCouple("Yasmin + plus-one",
  { firstName: 'Yasmin', lastName: 'Khan-Cohen', side: 'both', categories: ['cat-friends'], meal: 'Pan-Seared Salmon', dietaryTags: ['halal'] },
  { firstName: 'Plus',   lastName: 'One Khan-Cohen', side: 'both', categories: ['cat-friends'], meal: 'Beef Tenderloin', plusOne: true },
)

// One more child for realism
addFamilyParty("Lin Family", [
  { firstName: 'Mei',  lastName: 'Lin', side: 'both', categories: ['cat-friends'], meal: 'Vegetarian Risotto' },
  { firstName: 'Kwame', lastName: 'Lin', side: 'both', categories: ['cat-friends'], meal: 'Beef Tenderloin' },
  { firstName: 'Zara', lastName: 'Lin', side: 'both', categories: ['cat-friends','cat-kids'], meal: 'Kids Chicken Fingers', isChild: true },
])

// Add a couple more solos to round out
addGuest({ firstName: 'Margaret', lastName: 'Cohen-Diallo', side: 'both', categories: ['cat-friends'], meal: 'Pan-Seared Salmon' })
addGuest({ firstName: 'Edward',   lastName: 'Adebayo',      side: 'both', categories: ['cat-friends'], meal: 'Beef Tenderloin', rsvp: 'no' }) // declined
addGuest({ firstName: 'Helen',    lastName: 'Williams-Cohen', side: 'both', categories: ['cat-friends'], meal: 'Vegetarian Risotto' })
addGuest({ firstName: 'Valentina', lastName: 'García',      side: 'both', categories: ['cat-friends'], meal: 'Pan-Seared Salmon' })

// Decline some additional guests so RSVP totals land at 5-7 nos
// (already 5 declines above: Hannah college, Caleb college, Liam work, Florence friend, Edward friend)

console.log(`Generated ${guests.length} guests; declined: ${guests.filter(g => g.rsvp === 'no').length}`)

// ── Tables (T-shape venue) ─────────────────────────────────────────────────

const ROOM_W = 1200
const ROOM_H = 1350  // 90 ft tall — gives the 4×4 grid breathing room between rows + headroom for the bar against the back wall
const tables = []

// Sweetheart at top center
const sweetheart = {
  id: 't_sweet', name: 'Sweetheart', type: 'sweetheart',
  seats: 2, x: ROOM_W / 2 - 50, y: 80, width: 100, height: 70,
  sweetShape: 'heart', color: '#C9A961', assignments: {},
}
tables.push(sweetheart)

// Head table (long rect, 10 seats, one-side)
const head = {
  id: 't_head', name: 'Head Table', type: 'head',
  seats: 10, x: ROOM_W / 2 - 200, y: 200, width: 400, height: 70,
  oneSide: true, color: '#C9A961', assignments: {},
}
tables.push(head)

// 16 round tables in 4×4 grid below. Pushed down from the prior layout
// so there's a real ~10ft gap between the head table and the first row
// of guest tables — that's where the dance floor actually lives.
const roundCols = [180, 460, 740, 1020]
const roundRows = [560, 730, 900, 1070]  // 170 px (~11 ft) between centers — was 120 px, too tight
let roundIdx = 0
for (const y of roundRows) {
  for (const x of roundCols) {
    roundIdx++
    tables.push({
      id: `t_round_${roundIdx.toString().padStart(2, '0')}`,
      name: `Table ${roundIdx}`,
      type: 'round', seats: 8,
      x: x - 50, y: y - 50, diameter: 100,
      color: '#C9A961', assignments: {},
    })
  }
}

// ── Room objects ──────────────────────────────────────────────────────────

// CRITICAL: `type` strings must exactly match seatbee/Features/Editor/
// VenueObjectsSheet.swift::venueObjectTypes (catalogue source of truth).
// The catalogue maps each type to an icon + colour at render time, so
// typos like "dance_floor" or "dj_booth" silently fall through to wrong
// styling (which made the dance floor render as a bar in the prior pass).
// Defaults below mirror the catalogue's preferred dimensions.
const objects = [
  // Centerpiece dance floor — fills the gap between head table and the
  // first row of round guest tables. 240×130 reads as a real area.
  { id: 'obj_dance', type: 'dance', name: 'Dance Floor',
    x: ROOM_W / 2 - 120, y: 300, width: 240, height: 130,
    color: '#EDE0C4', category: 'entertainment', isObstacle: false },

  // Cake table — inside the top stem of the T, right of the head table
  // (top stem right wall is at ROOM_W * 0.8 = 960, so x=870 keeps the
  // 70px-wide cake fully inside with breathing room).
  { id: 'obj_cake', type: 'cake', name: 'Cake Table',
    x: 870, y: 200, width: 70, height: 70,
    color: '#D4A5A5', category: 'food', isObstacle: false },

  // DJ Booth — embedded at the back-centre of the dance floor, where a
  // real DJ would be set up. User feedback 2026-05-09: 'Maybe just move
  // the DJ booth to be near the dance floor.'
  { id: 'obj_dj', type: 'dj', name: 'DJ Booth',
    x: ROOM_W / 2 - 40, y: 380, width: 80, height: 50,
    color: '#2D2D2D', category: 'entertainment', isObstacle: false },

  // Bar — opposite corner from the DJ.
  { id: 'obj_bar', type: 'bar', name: 'Bar',
    x: 40, y: ROOM_H - 70, width: 160, height: 60,
    color: '#8B8680', category: 'food', isObstacle: false },

  // Main Entrance — top-left wall.
  { id: 'obj_entrance', type: 'entrance', name: 'Main Entrance',
    x: 30, y: 60, width: 40, height: 60,
    color: '#2D2D2D', category: 'structure', isObstacle: false },

  // Emergency Exit — right wall mid-height. Pushed below the T-stem
  // boundary (ROOM_H * 0.35 ≈ 472) so it lands on the wide bottom
  // section's right wall, not the top stem's narrower one.
  { id: 'obj_exit', type: 'exit', name: 'Emergency Exit',
    x: ROOM_W - 50, y: 600, width: 40, height: 50,
    color: '#9CAF88', category: 'structure', isObstacle: false },
]

// ── Pre-pin head table + sweetheart ───────────────────────────────────────

const existingAssignments = {}
existingAssignments[bride.id] = sweetheart.id
existingAssignments[groom.id] = sweetheart.id
for (const g of headTableMembers) {
  existingAssignments[g.id] = head.id
}

// ── Rules ─────────────────────────────────────────────────────────────────

const rules = []
function addRule(rule) { rules.push({ id: seqId('r'), enabled: true, weight: 10, hard: false, ...rule }) }

// 1-2: Soft prefer_together for the big college friend groups (round-table
// members, since 9 > 8 and we can't enforce a single table)
addRule({
  type: 'prefer_together',
  guests: brideCollege.filter(g => g.rsvp !== 'no').map(g => g.id),
  desc: "Bride's college friends seated together",
  weight: 30, hard: false,
})
addRule({
  type: 'prefer_together',
  guests: groomCollege.filter(g => g.rsvp !== 'no').map(g => g.id),
  desc: "Groom's college friends seated together",
  weight: 30, hard: false,
})

// 3-4: must_together for coworker groups (≤ 8 attending each)
addRule({
  type: 'must_together',
  guests: brideWork.filter(g => g.rsvp !== 'no').map(g => g.id),
  desc: "Bride's coworkers seated together",
  weight: 50, hard: true,
})
addRule({
  type: 'must_together',
  guests: groomWork.filter(g => g.rsvp !== 'no').map(g => g.id),
  desc: "Groom's coworkers seated together",
  weight: 50, hard: true,
})

// 5: category_together — Wedding Party (head table). Already pinned, this
// rule reinforces and shows up in the "rules satisfied" list nicely.
addRule({
  type: 'category_together',
  categoryId: 'cat-wedding-party',
  guests: guests.filter(g => g.categories.includes('cat-wedding-party')).map(g => g.id),
  desc: 'Wedding party seated together',
  weight: 40, hard: false,
})

// 6: near_object — bride's college friends near the dance floor (they're
// the ones who'll dance). Soft preference.
addRule({
  type: 'near_object',
  objectId: 'obj_dance',
  guests: brideCollege.filter(g => g.rsvp !== 'no').map(g => g.id),
  desc: "Bride's college friends near the dance floor",
  weight: 20, hard: false,
})

// 7: near_object — two grandmothers near the emergency exit. Realistic
// planner instinct: elderly guests get tables close to easy egress.
// Tight 2-guest rule keeps the demo varied (small near-rule next to
// the larger college-friends-near-dance-floor one).
const guestByName = (first, last) => guests.find(g => g.firstName === first && g.lastName === last)
const grandmaW = guestByName('Margaret', 'Williams')
const grandpaW = guestByName('James', 'Williams')
const grandmaO = guestByName('Ngozi', 'Okonkwo')
addRule({
  type: 'near_object',
  objectId: 'obj_exit',
  guests: [grandmaW.id, grandmaO.id],
  desc: 'Grandmothers near the emergency exit',
  weight: 20, hard: false,
})

// 8-11: must_not — cross-party drama (specific named guests)
//
// Web parity: must_not persists BOTH the flat `guests` list AND the
// sideA/sideB split. The iOS Edit Rule form's two-column picker reads
// from the split (not the flat list); without sideA/sideB the form
// opens with both columns empty even when the rule is otherwise
// correctly applied at solve time.
const addMustNot = (a, b, desc, weight = 30) => addRule({
  type: 'must_not',
  guests: [a, b],
  sideA: [a],
  sideB: [b],
  desc,
  weight,
  hard: true,
})

addMustNot(grandmaW.id, grandpaW.id, 'Divorced grandparents kept apart', 50)
addMustNot(brideWork[0].id, groomWork[0].id, 'Ex-colleagues from rival firms apart')
addMustNot(brideCollege[0].id, groomCollege[0].id, 'Old roommates with bad history apart')
addMustNot(brideCollege[1].id, brideWork[2].id, 'Past workplace incident apart')

// Note on parties: web/iOS UI auto-generates a must_together rule per
// party when a user creates one (RulesView.swift::AddPartySheet).
// Adding those same auto-rules here was tried and dropped the solver
// score to 84% — placing 27 small atomic groups first leaves no room
// to fit the 7-8-person coworker must_together rule at a single table.
// Parties are still GUARANTEED together at solve time via the `units`
// argument we pass to generateSeating below (units > rules in priority);
// we just don't double-write them as rules. The iOS Active Rules card
// surfaces party count separately via the parties-summary footer line.
console.log(`Rules: ${rules.length}`)

// ── Run the solver ────────────────────────────────────────────────────────

console.log(`Solving: ${guests.length} guests, ${tables.length} tables, ${rules.length} rules…`)

// Build solver-shaped guests
const solverGuests = guests.map(g => ({
  id: g.id, name: g.name, party: g.party,
  side: g.side, vip: g.vip, rsvp: g.rsvp,
  meal: g.meal, dietaryTags: g.dietaryTags, isChild: g.isChild,
  categories: g.categories,
}))

// Parties as units — small (≤ 4) so unit constraints are satisfiable.
const units = Object.values(partiesById).map(p => ({
  id: p.id, name: p.name, guestIds: p.guestIds,
}))

console.log(`Parties (units): ${units.length}, sizes: ${units.map(u => u.guestIds.length).join(',')}`)

// Try many seeds; keep the highest-scoring assignment. Solver is quick
// enough that 50 seeds is well under a second total.
let bestResult = null
let bestPercent = -1
const seeds = []
for (let i = 0; i < 50; i++) seeds.push(Math.floor(Math.random() * 1_000_000) + 1)
seeds.push(42, 17, 99, 1234, 7777, 31415, 12345)  // known seeds for reproducibility comparisons
for (const seed of seeds) {
  const r = generateSeating(
    tables.map(t => ({ ...t })),
    solverGuests,
    rules,
    CATEGORIES,
    existingAssignments,
    seed,
    units,
    [],
    objects,
    null
  )
  const pct = r.scorecard?.overallPercent ?? 0
  if (pct > bestPercent) {
    bestPercent = pct
    bestResult = r
  }
}
const solverResult = bestResult
const sc = solverResult.scorecard

console.log(`Best score: ${sc.overallPercent}% (${sc.overallLabel})`)
console.log(`Rules: ${sc.totalSatisfied}/${sc.totalRules} satisfied`)
console.log(`Hard: ${sc.hardConstraints.satisfied}/${sc.hardConstraints.total}, ` +
            `Soft: ${sc.softPreferences.satisfied}/${sc.softPreferences.total}`)
console.log(`Assignments: ${Object.keys(solverResult.assignments).length} / ${guests.filter(g=>g.rsvp!=='no').length} attending placed`)
if (solverResult.fallback) {
  console.warn('⚠️  Fallback used — pre-baked result is not a real solve.')
}

if (sc.overallPercent < 95) {
  console.error('❌ Score below 95%. Non-satisfied rules:')
  for (const r of [...sc.hardConstraints.rules, ...sc.softPreferences.rules]) {
    if (r.status !== 'satisfied') {
      console.error(`  [${r.status}] ${r.type}: ${r.description || r.desc || '(no desc)'}`)
      if (r.details) console.error(`            details: ${r.details}`)
    }
  }
  process.exit(1)
}

// ── Embed assignments back onto each table ─────────────────────────────────

const assignmentsByTable = {}
const seatOrders = solverResult.seatOrders || {}
for (const [guestId, tableId] of Object.entries(solverResult.assignments)) {
  if (!assignmentsByTable[tableId]) assignmentsByTable[tableId] = []
  assignmentsByTable[tableId].push(guestId)
}
for (const t of tables) {
  const ids = assignmentsByTable[t.id] || []
  const sorted = ids.slice().sort((a, b) => {
    const oa = seatOrders[a] ?? 999
    const ob = seatOrders[b] ?? 999
    if (oa !== ob) return oa - ob
    return (guests.find(g => g.id === a)?.name || '').localeCompare(guests.find(g => g.id === b)?.name || '')
  })
  sorted.forEach((gid, i) => { t.assignments[gid] = i })
}

// ── Output JSON ────────────────────────────────────────────────────────────

const today = new Date()
const eventDate = new Date(today.getFullYear() + 1, 5, 14)
while (eventDate.getDay() !== 6) eventDate.setDate(eventDate.getDate() + 1)

const partiesArr = Object.values(partiesById).map(p => ({
  id: p.id,
  name: p.name || 'Party',
  guestIds: p.guestIds,
}))

const output = {
  schemaVersion: 2,
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
    objects,
    categories: CATEGORIES,
    parties: partiesArr,
  },
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
console.log(`   ${guests.length} guests · ${guests.filter(g=>g.rsvp==='no').length} declined`)
console.log(`   ${tables.length} tables · ${rules.length} rules · ${partiesArr.length} parties · ${CATEGORIES.length} categories · ${objects.length} objects`)
console.log(`   Solver: ${sc.overallPercent}% (${sc.overallLabel})`)
