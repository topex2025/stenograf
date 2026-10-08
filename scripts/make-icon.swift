// Генератор иконки Стенографа: 1024×1024 PNG.
// Мотив: звуковая волна превращается в строки стенограммы — «речь → текст».
// Запуск: swift scripts/make-icon.swift <выход.png>

import AppKit
import CoreGraphics

let size = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("нет контекста") }

let w = CGFloat(size), h = CGFloat(size)

// Скруглённый квадрат на весь холст
let corner: CGFloat = 232
let rect = CGRect(x: 0, y: 0, width: w, height: h)
let shape = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.addPath(shape)
ctx.clip()

// Фон: диагональный градиент, глубокие чернила
let bgColors = [
    CGColor(red: 0.035, green: 0.05, blue: 0.10, alpha: 1),   // #0A0E1A
    CGColor(red: 0.09, green: 0.115, blue: 0.19, alpha: 1),   // #161E33
]
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])

// Лёгкое свечение в центре
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    CGColor(red: 1.0, green: 0.25, blue: 0.32, alpha: 0.16),
    CGColor(red: 1.0, green: 0.25, blue: 0.32, alpha: 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: w/2, y: h*0.56), startRadius: 0,
                       endCenter: CGPoint(x: w/2, y: h*0.56), endRadius: w*0.62,
                       options: [])

// Волна: столбики с амплитудой по синусу, градиент красный → янтарный по X
let barCount = 13
let barWidth: CGFloat = 30
let gap: CGFloat = (w - CGFloat(barCount) * barWidth) / (CGFloat(barCount) + 1)
let waveMidY = h * 0.60

func barColor(_ i: Int) -> CGColor {
    let t = CGFloat(i) / CGFloat(barCount - 1)
    let r = 1.0
    let g = 0.23 + t * (0.70 - 0.23)
    let b = 0.31 + t * (0.25 - 0.31)
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

for i in 0..<barCount {
    let t = CGFloat(i) / CGFloat(barCount - 1)
    // амплитуда: края ниже, центр выше + лёгкая асимметрия
    let envelope = sin(t * .pi)
    let wob = sin(t * 13.7) * 0.22 + sin(t * 5.3) * 0.16
    let amp = (envelope * 0.75 + 0.25 + wob * envelope) * 0.5
    let barH = max(0.12, min(1.0, amp)) * 240
    let x = gap + CGFloat(i) * (barWidth + gap)
    let barRect = CGRect(x: x, y: waveMidY - barH/2, width: barWidth, height: barH)
    let path = CGPath(roundedRect: barRect, cornerWidth: barWidth/2, cornerHeight: barWidth/2, transform: nil)
    // свечение
    ctx.setShadow(offset: .zero, blur: barH * 0.35,
                  color: CGColor(red: 1.0, green: 0.3, blue: 0.35, alpha: 0.45))
    ctx.setFillColor(barColor(i))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
}

// Строки стенограммы: три строки над волной, правая часть средней — «слово» из протокола
func line(_ y: CGFloat, _ x: CGFloat, _ width: CGFloat, _ alpha: CGFloat) {
    let r = CGRect(x: x, y: y, width: width, height: 22)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.fillPath()
}

let leftX: CGFloat = 152
line(h * 0.475, leftX, 600, 0.30)                                  // верхняя строка
line(h * 0.395, leftX, 300, 0.20)                                  // короткая
// средняя строка с красной «выделенной фразой»
line(h * 0.435, leftX, 230, 0.24)
let word = CGRect(x: leftX + 250, y: h * 0.432, width: 150, height: 28)
ctx.setFillColor(CGColor(red: 1.0, green: 0.23, blue: 0.31, alpha: 0.95))
ctx.addPath(CGPath(roundedRect: word, cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.fillPath()
line(h * 0.435, leftX + 250 + 170, leftX + 600 - (leftX + 250 + 170) + 30, 0.24)

// Точка записи над волной — маленький красный кружок
ctx.setFillColor(CGColor(red: 1.0, green: 0.23, blue: 0.31, alpha: 1))
ctx.fillEllipse(in: CGRect(x: w/2 - 9, y: h*0.60 + 190, width: 18, height: 18))
// пульс вокруг точки
ctx.setStrokeColor(CGColor(red: 1.0, green: 0.23, blue: 0.31, alpha: 0.5))
ctx.setLineWidth(5)
ctx.strokeEllipse(in: CGRect(x: w/2 - 22, y: h*0.60 + 177, width: 44, height: 44))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { fatalError("не удалось собрать PNG") }
try png.write(to: URL(fileURLWithPath: outPath))
print("иконка записана: \(outPath)")
