import UIKit
import SwiftUI

// MARK: - Canvas Data Protocol

protocol CanvasDelegate: AnyObject {
    func canvasDidSelectTable(_ tableId: String)
    func canvasDidSelectObject(_ objectId: String)
    func canvasDidDeselectAll()
    func canvasDidMoveTable(_ tableId: String, x: Double, y: Double)
    func canvasDidMoveObject(_ objectId: String, x: Double, y: Double)
    func canvasDidRequestDeleteObject(_ objectId: String)
}

// MARK: - Canvas View Controller

class CanvasViewController: UIViewController, UIScrollViewDelegate {
    weak var delegate: CanvasDelegate?

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private var tableViews: [String: CanvasTableView] = [:]
    private var objectViews: [String: CanvasObjectView] = [:]

    private var selectedId: String?
    private var selectedType: String? // "table" or "object"

    // Content size — large enough for most venues
    private let canvasSize = CGSize(width: 2000, height: 2000)
    private let canvasOrigin = CGPoint(x: 400, y: 400) // offset so objects start visible

    override func viewDidLoad() {
        super.viewDidLoad()

        // Scroll view setup
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.3
        scrollView.maximumZoomScale = 3.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = UIColor(red: 250/255, green: 246/255, blue: 236/255, alpha: 1) // ivory2

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Content view
        contentView.frame = CGRect(origin: .zero, size: canvasSize)
        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)
        scrollView.contentSize = canvasSize

        // Dot pattern background
        let dotLayer = DotPatternLayer()
        dotLayer.frame = contentView.bounds
        contentView.layer.insertSublayer(dotLayer, at: 0)

        // Tap to deselect
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        contentView.addGestureRecognizer(tap)

        // Initial zoom
        scrollView.zoomScale = 0.8

        // Center content
        DispatchQueue.main.async {
            let offsetX = max(0, (self.canvasSize.width * 0.8 - self.scrollView.bounds.width) / 2)
            let offsetY = max(0, (self.canvasSize.height * 0.8 - self.scrollView.bounds.height) / 2)
            self.scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentView
    }

    // MARK: - Update from SwiftUI

    func updateTables(_ tables: [SeatTable], guests: [Guest], selectedId: String?) {
        self.selectedId = selectedId

        let currentIds = Set(tableViews.keys)
        let newIds = Set(tables.map(\.id))

        // Remove deleted
        for id in currentIds.subtracting(newIds) {
            tableViews[id]?.removeFromSuperview()
            tableViews.removeValue(forKey: id)
        }

        // Add or update
        for table in tables {
            if let existing = tableViews[table.id] {
                existing.update(table: table, guests: guests, isSelected: table.id == selectedId)
                existing.center = CGPoint(x: canvasOrigin.x + table.x, y: canvasOrigin.y + table.y)
            } else {
                let tv = CanvasTableView(table: table, guests: guests, isSelected: table.id == selectedId)
                tv.center = CGPoint(x: canvasOrigin.x + table.x, y: canvasOrigin.y + table.y)
                tv.onTap = { [weak self] in
                    self?.selectTable(table.id)
                }
                tv.onDragEnd = { [weak self] center in
                    let x = Double(center.x - (self?.canvasOrigin.x ?? 0))
                    let y = Double(center.y - (self?.canvasOrigin.y ?? 0))
                    self?.delegate?.canvasDidMoveTable(table.id, x: x, y: y)
                }
                contentView.addSubview(tv)
                tableViews[table.id] = tv
            }
        }
    }

    func updateObjects(_ objects: [RoomObject], selectedId: String?) {
        let currentIds = Set(objectViews.keys)
        let newIds = Set(objects.map(\.id))

        for id in currentIds.subtracting(newIds) {
            objectViews[id]?.removeFromSuperview()
            objectViews.removeValue(forKey: id)
        }

        for obj in objects {
            if let existing = objectViews[obj.id] {
                existing.update(object: obj, isSelected: obj.id == selectedId)
                existing.center = CGPoint(x: canvasOrigin.x + obj.x, y: canvasOrigin.y + obj.y)
            } else {
                let ov = CanvasObjectView(object: obj, isSelected: obj.id == selectedId)
                ov.center = CGPoint(x: canvasOrigin.x + obj.x, y: canvasOrigin.y + obj.y)
                ov.onTap = { [weak self] in
                    self?.selectObject(obj.id)
                }
                ov.onDragEnd = { [weak self] center in
                    let x = Double(center.x - (self?.canvasOrigin.x ?? 0))
                    let y = Double(center.y - (self?.canvasOrigin.y ?? 0))
                    self?.delegate?.canvasDidMoveObject(obj.id, x: x, y: y)
                }
                contentView.addSubview(ov)
                objectViews[obj.id] = ov
            }
        }
    }

    // MARK: - Selection

    private func selectTable(_ id: String) {
        selectedId = id
        selectedType = "table"
        updateSelectionVisuals()
        delegate?.canvasDidSelectTable(id)
    }

    private func selectObject(_ id: String) {
        selectedId = id
        selectedType = "object"
        updateSelectionVisuals()
        delegate?.canvasDidSelectObject(id)
    }

    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: contentView)
        // Check if tap hit any item
        for (_, tv) in tableViews {
            if tv.frame.contains(location) { return }
        }
        for (_, ov) in objectViews {
            if ov.frame.contains(location) { return }
        }
        // Tapped empty space
        selectedId = nil
        selectedType = nil
        updateSelectionVisuals()
        delegate?.canvasDidDeselectAll()
    }

    private func updateSelectionVisuals() {
        for (id, tv) in tableViews {
            tv.setSelected(id == selectedId)
        }
        for (id, ov) in objectViews {
            ov.setSelected(id == selectedId)
        }
    }
}

// MARK: - Dot Pattern Layer

class DotPatternLayer: CALayer {
    override func draw(in ctx: CGContext) {
        let spacing: CGFloat = 18
        let dotSize: CGFloat = 2
        let gold = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 0.12)

        ctx.setFillColor(gold.cgColor)
        var x: CGFloat = spacing
        while x < bounds.width {
            var y: CGFloat = spacing
            while y < bounds.height {
                ctx.fillEllipse(in: CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize))
                y += spacing
            }
            x += spacing
        }
    }
}

// MARK: - Draggable Table View

class CanvasTableView: UIView {
    var onTap: (() -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?

    private var table: SeatTable
    private var isItemSelected = false

    // Padding around the body for seats (~14pt outside) + selection ring + label slack.
    private let padding: CGFloat = 28

    private let shapeLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private let label = UILabel()
    private var seatLayers: [CAShapeLayer] = []

    init(table: SeatTable, guests: [Guest], isSelected: Bool) {
        self.table = table
        self.isItemSelected = isSelected
        super.init(frame: .zero)
        setupView()
        update(table: table, guests: guests, isSelected: isSelected)
        setupGestures()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupView() {
        backgroundColor = .clear

        selectionLayer.strokeColor = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 1).cgColor
        selectionLayer.fillColor = UIColor.clear.cgColor
        selectionLayer.lineWidth = 2
        selectionLayer.lineDashPattern = [4, 3]
        selectionLayer.isHidden = true
        layer.addSublayer(selectionLayer)

        shapeLayer.strokeColor = UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 0.15).cgColor
        shapeLayer.lineWidth = 1
        layer.addSublayer(shapeLayer)

        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 1)
        addSubview(label)
    }

    func update(table: SeatTable, guests: [Guest], isSelected: Bool) {
        self.table = table
        self.isItemSelected = isSelected

        let body = CanvasTableView.bodySize(for: table)
        let savedCenter = self.center
        frame.size = CGSize(width: body.width + padding * 2, height: body.height + padding * 2)
        if savedCenter != .zero { self.center = savedCenter }

        let bodyCenter = CGPoint(x: padding + body.width/2, y: padding + body.height/2)

        let bodyPath = CanvasTableView.shapePath(for: table, body: body, center: bodyCenter)
        shapeLayer.path = bodyPath.cgPath
        let fallbackFill = UIColor(red: 247/255, green: 231/255, blue: 206/255, alpha: 1)
        shapeLayer.fillColor = (UIColor(hex: table.color ?? "") ?? fallbackFill).cgColor

        let selPath = CanvasTableView.selectionPath(for: table, body: body, center: bodyCenter)
        selectionLayer.path = selPath.cgPath
        selectionLayer.isHidden = !isSelected

        label.text = table.name
        label.frame = CGRect(x: padding, y: bodyCenter.y - 6, width: body.width, height: 12)

        seatLayers.forEach { $0.removeFromSuperlayer() }
        seatLayers = []

        let dotSize: CGFloat = 8
        let gold = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 1)
        let empty = UIColor(red: 255/255, green: 254/255, blue: 249/255, alpha: 1)
        let emptyStroke = UIColor(red: 185/255, green: 179/255, blue: 166/255, alpha: 1)

        let seatPositions = CanvasTableView.seatPositions(for: table, body: body, center: bodyCenter)
        for (i, pos) in seatPositions.enumerated() {
            let dot = CAShapeLayer()
            let r = CGRect(x: pos.x - dotSize/2, y: pos.y - dotSize/2, width: dotSize, height: dotSize)
            dot.path = UIBezierPath(ovalIn: r).cgPath
            if i < table.filledCount {
                dot.fillColor = gold.cgColor
                dot.strokeColor = gold.cgColor
            } else {
                dot.fillColor = empty.cgColor
                dot.strokeColor = emptyStroke.cgColor
            }
            dot.lineWidth = 1
            layer.addSublayer(dot)
            seatLayers.append(dot)
        }

        applyTransform(animated: false)
    }

    func setSelected(_ selected: Bool) {
        isItemSelected = selected
        selectionLayer.isHidden = !selected
        UIView.animate(withDuration: 0.2) {
            self.applyTransform(animated: true)
        }
    }

    private func applyTransform(animated: Bool) {
        let rotation = CGFloat((table.rotation ?? 0) * .pi / 180)
        let scale: CGFloat = isItemSelected ? 1.06 : 1.0
        transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
    }

    // MARK: - Shape geometry (mirrors web `Table` component in src/App.jsx)

    private static func bodySize(for table: SeatTable) -> CGSize {
        switch table.type {
        case .round:
            let d = CGFloat(table.diameter ?? 90)
            return CGSize(width: d, height: d)
        case .rect:
            return CGSize(width: CGFloat(table.width ?? 100), height: CGFloat(table.height ?? 50))
        case .head:
            return CGSize(width: CGFloat(table.width ?? 280), height: CGFloat(table.height ?? 50))
        case .sweetheart:
            return CGSize(width: CGFloat(table.width ?? 100), height: CGFloat(table.height ?? 60))
        }
    }

    private static func shapePath(for table: SeatTable, body: CGSize, center c: CGPoint) -> UIBezierPath {
        switch table.type {
        case .round:
            return UIBezierPath(arcCenter: c, radius: body.width / 2,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        case .rect, .head:
            let rect = CGRect(x: c.x - body.width/2, y: c.y - body.height/2,
                              width: body.width, height: body.height)
            return UIBezierPath(roundedRect: rect, cornerRadius: 6)
        case .sweetheart:
            return sweetheartPath(shape: table.sweetShape, body: body, center: c)
        }
    }

    private static func selectionPath(for table: SeatTable, body: CGSize, center c: CGPoint) -> UIBezierPath {
        switch table.type {
        case .round:
            return UIBezierPath(arcCenter: c, radius: body.width / 2 + 10,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        case .rect, .head:
            let rect = CGRect(x: c.x - body.width/2 - 6, y: c.y - body.height/2 - 6,
                              width: body.width + 12, height: body.height + 12)
            return UIBezierPath(roundedRect: rect, cornerRadius: 10)
        case .sweetheart:
            let inflated = CGSize(width: body.width + 12, height: body.height + 12)
            return sweetheartPath(shape: table.sweetShape, body: inflated, center: c)
        }
    }

    private static func sweetheartPath(shape: String?, body: CGSize, center c: CGPoint) -> UIBezierPath {
        let w = body.width
        let h = body.height
        switch (shape ?? "heart").lowercased() {
        case "oval":
            return UIBezierPath(ovalIn: CGRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h))
        case "diamond", "rect", "rectangle":
            return UIBezierPath(roundedRect: CGRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h), cornerRadius: 8)
        default: // heart — matches web SweetheartShape quadratic-curve path
            let path = UIBezierPath()
            path.move(to: CGPoint(x: c.x - w/2, y: c.y))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h/2),
                              controlPoint: CGPoint(x: c.x - w/2, y: c.y - h/2))
            path.addQuadCurve(to: CGPoint(x: c.x + w/2, y: c.y),
                              controlPoint: CGPoint(x: c.x + w/2, y: c.y - h/2))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h/2),
                              controlPoint: CGPoint(x: c.x + w/2, y: c.y + h/3))
            path.addQuadCurve(to: CGPoint(x: c.x - w/2, y: c.y),
                              controlPoint: CGPoint(x: c.x - w/2, y: c.y + h/3))
            path.close()
            return path
        }
    }

    private static func seatPositions(for table: SeatTable, body: CGSize, center c: CGPoint) -> [CGPoint] {
        let n = max(0, table.seats)
        guard n > 0 else { return [] }
        let offset: CGFloat = 14

        switch table.type {
        case .round:
            let r = body.width / 2
            return (0..<n).map { i in
                let ang = CGFloat(i) / CGFloat(n) * .pi * 2 - .pi / 2
                return CGPoint(x: c.x + cos(ang) * (r + offset),
                               y: c.y + sin(ang) * (r + offset))
            }
        case .sweetheart:
            // Web hardcodes 2 seats at the bottom regardless of seat count.
            let count = min(n, 2)
            let y = c.y + body.height/2 + offset
            if count == 1 { return [CGPoint(x: c.x, y: y)] }
            return [
                CGPoint(x: c.x - body.width/4, y: y),
                CGPoint(x: c.x + body.width/4, y: y),
            ]
        case .rect, .head:
            let w = body.width
            let h = body.height
            if table.oneSide == true {
                let sp = w / CGFloat(n + 1)
                return (0..<n).map { i in
                    CGPoint(x: c.x - w/2 + sp * CGFloat(i + 1), y: c.y - h/2 - offset)
                }
            }
            // Default two-side: top + bottom edges, with top getting the extra when odd.
            let top = (n + 1) / 2
            let bot = n - top
            let sp = w / CGFloat(max(top, bot) + 1)
            var seats: [CGPoint] = []
            for i in 0..<top {
                seats.append(CGPoint(x: c.x - w/2 + sp * CGFloat(i + 1), y: c.y - h/2 - offset))
            }
            for i in 0..<bot {
                seats.append(CGPoint(x: c.x - w/2 + sp * CGFloat(i + 1), y: c.y + h/2 + offset))
            }
            return seats
        }
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        isUserInteractionEnabled = true
    }

    @objc private func handleTap() {
        onTap?()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .changed:
            center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
            gesture.setTranslation(.zero, in: superview)
        case .ended, .cancelled:
            onDragEnd?(center)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        default: break
        }
    }
}

// MARK: - Draggable Object View

class CanvasObjectView: UIView {
    var onTap: (() -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?

    private var object: RoomObject
    private var isItemSelected = false

    private let iconView = UIImageView()
    private let nameLabel = UILabel()

    init(object: RoomObject, isSelected: Bool) {
        self.object = object
        self.isItemSelected = isSelected
        super.init(frame: CGRect(x: 0, y: 0, width: object.width, height: object.height))
        setupView()
        update(object: object, isSelected: isSelected)
        setupGestures()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupView() {
        layer.cornerRadius = 8
        clipsToBounds = true

        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)

        nameLabel.textAlignment = .center
        nameLabel.font = UIFont.systemFont(ofSize: 9, weight: .medium)
        addSubview(nameLabel)
    }

    func update(object: RoomObject, isSelected: Bool) {
        self.object = object
        self.isItemSelected = isSelected
        frame.size = CGSize(width: object.width, height: object.height)

        let def = venueObjectTypes.first { $0.type == object.type }
        let colorHex = def?.color ?? "#8B8680"
        backgroundColor = UIColor(hex: colorHex)?.withAlphaComponent(0.85)

        let isDark = colorHex == "#2D2D2D"
        let textColor: UIColor = isDark ? .white : UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 0.7)

        let symbolName = def?.icon ?? "questionmark.circle"
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: config)?
            .withRenderingMode(.alwaysTemplate)
        iconView.tintColor = textColor
        let iconSize: CGFloat = 24
        iconView.frame = CGRect(
            x: (bounds.width - iconSize) / 2,
            y: bounds.height/2 - iconSize - 2,
            width: iconSize,
            height: iconSize
        )

        nameLabel.text = object.name
        nameLabel.textColor = isDark ? .white : UIColor(red: 45/255, green: 45/255, blue: 45/255, alpha: 1)
        nameLabel.frame = CGRect(x: 4, y: bounds.height/2 + 4, width: bounds.width - 8, height: 14)

        layer.borderWidth = isSelected ? 2 : 0
        layer.borderColor = UIColor(red: 201/255, green: 169/255, blue: 97/255, alpha: 1).cgColor

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = isSelected ? 0.2 : 0.1
        layer.shadowRadius = isSelected ? 8 : 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    func setSelected(_ selected: Bool) {
        isItemSelected = selected
        UIView.animate(withDuration: 0.2) {
            self.layer.borderWidth = selected ? 2 : 0
            self.layer.shadowOpacity = selected ? 0.2 : 0.1
        }
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        isUserInteractionEnabled = true
    }

    @objc private func handleTap() {
        onTap?()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .changed:
            center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
            gesture.setTranslation(.zero, in: superview)
        case .ended, .cancelled:
            onDragEnd?(center)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        default: break
        }
    }
}

// MARK: - UIColor hex helper

extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: return nil
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

// MARK: - SwiftUI Wrapper

struct CanvasViewRepresentable: UIViewControllerRepresentable {
    let tables: [SeatTable]
    let objects: [RoomObject]
    let guests: [Guest]
    let selectedTableId: String?
    let selectedObjectId: String?

    var onSelectTable: (String) -> Void
    var onSelectObject: (String) -> Void
    var onDeselectAll: () -> Void
    var onMoveTable: (String, Double, Double) -> Void
    var onMoveObject: (String, Double, Double) -> Void

    func makeUIViewController(context: Context) -> CanvasViewController {
        let vc = CanvasViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: CanvasViewController, context: Context) {
        vc.updateTables(tables, guests: guests, selectedId: selectedTableId)
        vc.updateObjects(objects, selectedId: selectedObjectId)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CanvasDelegate {
        let parent: CanvasViewRepresentable

        init(_ parent: CanvasViewRepresentable) {
            self.parent = parent
        }

        func canvasDidSelectTable(_ tableId: String) {
            parent.onSelectTable(tableId)
        }

        func canvasDidSelectObject(_ objectId: String) {
            parent.onSelectObject(objectId)
        }

        func canvasDidDeselectAll() {
            parent.onDeselectAll()
        }

        func canvasDidMoveTable(_ tableId: String, x: Double, y: Double) {
            parent.onMoveTable(tableId, x, y)
        }

        func canvasDidMoveObject(_ objectId: String, x: Double, y: Double) {
            parent.onMoveObject(objectId, x, y)
        }

        func canvasDidRequestDeleteObject(_ objectId: String) {}
    }
}
