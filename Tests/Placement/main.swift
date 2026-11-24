import AppKit
for (screen,height) in [(CGRect(x:0,y:0,width:1800,height:1169),39.0),
                        (CGRect(x:-381,y:1169,width:2560,height:1440),30.0)] {
    for size in [CGSize(width:308,height:44),CGSize(width:248,height:236)] {
        let bottom = screen.maxY - height
        for x in [screen.minX+2,screen.midX,screen.maxX-2] {
            let frame = MenuPlacement.volumeFrame(size:size,horizontal:x,barBottom:bottom,screen:screen)
            precondition(frame.maxY == bottom - 1 && screen.contains(frame))
            let click = CGPoint(x:x,y:screen.maxY-14)
            let menu = MenuPlacement.menuTop(click:click,barBottom:bottom,width:145,screen:screen)
            precondition(menu.y < click.y && menu.y <= bottom && menu.x + 145 <= screen.maxX)
        }
    }
}
print("Built-in and BenQ menu geometry and edge cases passed.")
