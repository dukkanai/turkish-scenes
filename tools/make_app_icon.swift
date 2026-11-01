import AppKit
import Foundation
let root = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
func render(size: Int, name: String) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size)/1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    NSColor(calibratedRed: 0.04, green: 0.30, blue: 0.32, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0,y: 0,width: 1024,height: 1024)).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 150,y: 220,width: 724,height: 584),xRadius: 54,yRadius: 54).fill()
    NSColor(calibratedRed: 0.04, green: 0.30, blue: 0.32, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 210,y: 310,width: 604,height: 404),xRadius: 20,yRadius: 20).fill()
    for x in stride(from: 220, through: 740, by: 130) {
        NSBezierPath(roundedRect:NSRect(x:CGFloat(x),y:245,width:65,height:36),xRadius:8,yRadius:8).fill()
        NSBezierPath(roundedRect:NSRect(x:CGFloat(x),y:742,width:65,height:36),xRadius:8,yRadius:8).fill()
    }
    NSColor(calibratedRed: 1,green: 0.76,blue: 0.31,alpha: 1).setFill()
    let play=NSBezierPath();play.move(to:NSPoint(x:430,y:385));play.line(to:NSPoint(x:430,y:639));play.line(to:NSPoint(x:650,y:512));play.close();play.fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using:.png,properties:[:])!.write(to: root.appendingPathComponent(name))
}
let icons:[(Int,String,String,String)] = [(120,"icon-120.png","iphone","60x60"),(180,"icon-180.png","iphone","60x60"),(80,"icon-80.png","iphone","40x40"),(87,"icon-87.png","iphone","29x29"),(58,"icon-58.png","iphone","29x29"),(40,"icon-40.png","iphone","20x20"),(60,"icon-60.png","iphone","20x20"),(1024,"icon-1024.png","ios-marketing","1024x1024")]
var items:[[String:String]]=[["idiom":"iphone","size":"40x40","scale":"3x","filename":"icon-120.png"]]
for (size,name,idiom,points) in icons {
    try render(size:size,name:name)
    let base=Double(points.split(separator:"x")[0])!
    items.append(["idiom":idiom,"size":points,"scale":"\(Int(Double(size)/base))x","filename":name])
}
let data=try JSONSerialization.data(withJSONObject:["images":items,"info":["version":1,"author":"xcode"]],options:[.prettyPrinted,.sortedKeys])
try data.write(to:root.appendingPathComponent("Contents.json"))
print("Generated original opaque app icons.")
