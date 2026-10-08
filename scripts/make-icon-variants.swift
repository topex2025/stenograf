// Три варианта иконки Стенографа + общий холст для выбора.
// Запуск: swift scripts/make-icon-variants.swift /tmp
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
let S: CGFloat = 1024

func canvas(_ clip: Bool = true) -> (NSImage, CGContext) {
    let img = NSImage(size: NSSize(width: S, height: S))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    if clip {
        let shape = CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S), cornerWidth: 232, cornerHeight: 232, transform: nil)
        ctx.addPath(shape)
        ctx.clip()
    }
    return (img, ctx)
}

func gradient(_ ctx: CGContext, _ colors: [CGColor], _ start: CGPoint, _ end: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: start, end: end, options: [])
}

func save(_ img: NSImage, _ name: String) {
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("png \(name)") }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("записан \(name)")
}

// ── Вариант A: монограмма «С» на сочном градиенте ─────────────────────────
do {
    let (img, ctx) = canvas()
    gradient(ctx, [
        CGColor(red: 1.00, green: 0.20, blue: 0.28, alpha: 1),   // сочный красный
        CGColor(red: 1.00, green: 0.45, blue: 0.15, alpha: 1),   // янтарный
    ], CGPoint(x: 0, y: S), CGPoint(x: S, y: 0))
    // лёгкая внутренняя подсветка сверху
    gradient(ctx, [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ], CGPoint(x: S/2, y: S), CGPoint(x: S/2, y: S*0.55))
    // огромная С
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 640, weight: .black),
        .foregroundColor: NSColor.white,
    ]
    let str = NSAttributedString(string: "С", attributes: attrs)
    let sz = str.size()
    // тень-углубление
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 46,
                  color: CGColor(red: 0.4, green: 0.02, blue: 0.06, alpha: 0.55))
    str.draw(at: NSPoint(x: (S - sz.width)/2 - 24, y: (S - sz.height)/2))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // маленькая точка записи справа от С — «идёт запись»
    ctx.setFillColor(CGColor(red: 0.10, green: 0.02, blue: 0.04, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 800, y: 700, width: 78, height: 78))
    save(img, "icon-A.png")
}

// ── Вариант B: микрофон на чернилах ────────────────────────────────────────
do {
    let (img, ctx) = canvas()
    gradient(ctx, [
        CGColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1),
        CGColor(red: 0.13, green: 0.15, blue: 0.26, alpha: 1),
    ], CGPoint(x: 0, y: S), CGPoint(x: S, y: 0))
    // корпус микрофона: капсула
    let micRect = CGRect(x: S/2 - 165, y: S/2 - 40, width: 330, height: 420)
    ctx.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1))
    ctx.setShadow(offset: .zero, blur: 60, color: CGColor(red: 1.0, green: 0.3, blue: 0.35, alpha: 0.35))
    ctx.addPath(CGPath(roundedRect: micRect, cornerWidth: 165, cornerHeight: 165, transform: nil))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // дужка
    ctx.setStrokeColor(CGColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1))
    ctx.setLineWidth(42)
    ctx.strokeEllipse(in: CGRect(x: S/2 - 250, y: S/2 - 10, width: 500, height: 320))
    // ножка и основание
    ctx.setLineWidth(42)
    ctx.move(to: CGPoint(x: S/2, y: S/2 - 10)); ctx.addLine(to: CGPoint(x: S/2, y: S/2 - 160)); ctx.strokePath()
    ctx.setLineWidth(54)
    ctx.move(to: CGPoint(x: S/2 - 140, y: S/2 - 170)); ctx.addLine(to: CGPoint(x: S/2 + 140, y: S/2 - 170)); ctx.strokePath()
    // сетка микрофона: тонкие тёмные полоски
    ctx.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 0.18))
    for i in 0..<3 {
        let y = S/2 + 210 - CGFloat(i) * 92
        ctx.fill(CGRect(x: S/2 - 118, y: y, width: 236, height: 26))
    }
    // красная точка записи на капсуле
    ctx.setFillColor(CGColor(red: 1.0, green: 0.23, blue: 0.31, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: S/2 - 34, y: S/2 + 120, width: 68, height: 68))
    save(img, "icon-B.png")
}

// ── Вариант C: лист протокола с красной печатью ────────────────────────────
do {
    let (img, ctx) = canvas()
    gradient(ctx, [
        CGColor(red: 0.99, green: 0.96, blue: 0.90, alpha: 1),   // тёплая бумага
        CGColor(red: 0.95, green: 0.90, blue: 0.80, alpha: 1),
    ], CGPoint(x: 0, y: S), CGPoint(x: S, y: 0))
    // строки протокола — чернильные, одна «фраза» красная
    let ink = CGColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1)
    func ln(_ y: CGFloat, _ x: CGFloat, _ w: CGFloat, color: CGColor = CGColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1)) {
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil))
        ctx.fillPath()
    }
    ln(700, 170, 520)                     // заголовок потолще
    ln(610, 170, 640)
    ln(530, 170, 300)
    ln(530, 500, 200, color: CGColor(red: 1.0, green: 0.23, blue: 0.31, alpha: 1))  // красная «фраза»
    ln(450, 170, 560)
    ln(370, 170, 420)
    // волна внизу листа: речь
    for i in 0..<15 {
        let t = CGFloat(i) / 14
        let env = sin(t * .pi)
        let bh = (0.3 + 0.7 * env) * 120
        let bw: CGFloat = 26
        let gap: CGFloat = (560 - 15 * bw) / 16
        let x = 170 + CGFloat(i) * (bw + gap)
        let r = CGRect(x: x, y: 230 - bh/2, width: bw, height: bh)
        ctx.setFillColor(CGColor(red: 0.10 + 0.9 * t, green: 0.10 + 0.13 * t, blue: 0.13 + 0.18 * t, alpha: 1))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: bw/2, cornerHeight: bw/2, transform: nil))
        ctx.fillPath()
    }
    // красная печать-кружок с краю
    ctx.setFillColor(CGColor(red: 1.0, green: 0.23, blue: 0.31, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 720, y: 220, width: 150, height: 150))
    ctx.setFillColor(CGColor(red: 0.99, green: 0.96, blue: 0.90, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 748, y: 248, width: 94, height: 94))
    _ = ink
    save(img, "icon-C.png")
}

// ── Холст выбора: три иконки в ряд с буквами ───────────────────────────────
do {
    let W: CGFloat = 3 * 360 + 4 * 40, H: CGFloat = 480
    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
    let letterAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 44, weight: .heavy),
        .foregroundColor: NSColor.white,
    ]
    for (i, name) in ["A", "B", "C"].enumerated() {
        let icon = NSImage(contentsOfFile: "\(outDir)/icon-\(name).png")!
        let x = CGFloat(40 + i * 400)
        icon.draw(in: NSRect(x: x + 30, y: 110, width: 300, height: 300))
        NSAttributedString(string: name, attributes: letterAttrs)
            .draw(at: NSPoint(x: x + 160, y: 40))
    }
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("chooser") }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/icons-chooser.png"))
    print("записан icons-chooser.png")
}
