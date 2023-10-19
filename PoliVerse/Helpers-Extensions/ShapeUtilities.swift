//
//  ShapeUtilities.swift
//  PoliVerse
//
//  Created by Samuele Segrini on 20/10/23.
//

import SwiftUI

struct RoundedCornersShape: Shape {
    var corners: UIRectCorner
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let topLeft = corners.contains(.topLeft)
        let topRight = corners.contains(.topRight)
        let bottomLeft = corners.contains(.bottomLeft)
        let bottomRight = corners.contains(.bottomRight)

        let width = rect.size.width
        let height = rect.size.height

        let tradius = min(min(radius, width / 2), height / 2)

        path.move(to: CGPoint(x: width / 2, y: 0))

        if topRight {
            path.addArc(center: CGPoint(x: width - tradius, y: tradius), radius: tradius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: width, y: 0))
            path.addLine(to: CGPoint(x: width, y: tradius))
        }

        if bottomRight {
            path.addArc(center: CGPoint(x: width - tradius, y: height - tradius), radius: tradius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: width - tradius, y: height))
        }

        if bottomLeft {
            path.addArc(center: CGPoint(x: tradius, y: height - tradius), radius: tradius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: 0, y: height))
            path.addLine(to: CGPoint(x: 0, y: height - tradius))
        }

        if topLeft {
            path.addArc(center: CGPoint(x: tradius, y: tradius), radius: tradius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: tradius, y: 0))
        }

        return path
    }
}

struct CurvedRightTriangle: Shape {
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.minX+50, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY+50))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        
        return path
    }
}
