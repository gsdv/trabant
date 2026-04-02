import SwiftUI

struct AnimatedDashboardBackdrop: View {
    private let blobSpecs: [BackdropBlobSpec] = [
        BackdropBlobSpec(
            color: TrabantTheme.dashboardGlowPrimary,
            opacity: 0.26,
            size: CGSize(width: 760, height: 680),
            blurRadius: 120,
            anchor: CGPoint(x: 0.26, y: 0.24),
            orbit: CGSize(width: 120, height: 92),
            speed: 0.07,
            phase: 0.3,
            rotation: -16
        ),
        BackdropBlobSpec(
            color: TrabantTheme.dashboardGlowSecondary,
            opacity: 0.19,
            size: CGSize(width: 860, height: 720),
            blurRadius: 130,
            anchor: CGPoint(x: 0.72, y: 0.29),
            orbit: CGSize(width: 146, height: 104),
            speed: 0.06,
            phase: 1.7,
            rotation: 21
        ),
        BackdropBlobSpec(
            color: TrabantTheme.dashboardGlowTertiary,
            opacity: 0.16,
            size: CGSize(width: 720, height: 620),
            blurRadius: 116,
            anchor: CGPoint(x: 0.66, y: 0.78),
            orbit: CGSize(width: 118, height: 128),
            speed: 0.05,
            phase: 2.9,
            rotation: -10
        )
    ]

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    LinearGradient(
                        colors: [
                            TrabantTheme.dashboardBackdropTop,
                            TrabantTheme.windowBackground,
                            TrabantTheme.dashboardBackdropBottom
                        ],
                        startPoint: UnitPoint(
                            x: 0.12 + CGFloat(sin(time * 0.03) * 0.04),
                            y: 0.04
                        ),
                        endPoint: UnitPoint(
                            x: 0.88 + CGFloat(cos(time * 0.025) * 0.05),
                            y: 0.96
                        )
                    )

                    ForEach(Array(blobSpecs.enumerated()), id: \.offset) { index, spec in
                        let position = spec.position(in: geometry.size, time: time)
                        let wobble = spec.wobble(time: time)

                        MorphingBackdropBlob(time: time, phase: spec.phase)
                            .fill(spec.color.opacity(spec.opacity))
                            .frame(
                                width: spec.size.width * wobble.width,
                                height: spec.size.height * wobble.height
                            )
                            .rotationEffect(.degrees(spec.rotation + spec.rotationDrift(time: time)))
                            .position(position)
                            .blur(radius: spec.blurRadius)
                            .blendMode(index == 0 ? .screen : .plusLighter)
                    }

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.14),
                            Color.clear,
                            Color.black.opacity(0.22)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .compositingGroup()
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct BackdropBlobSpec {
    let color: Color
    let opacity: Double
    let size: CGSize
    let blurRadius: CGFloat
    let anchor: CGPoint
    let orbit: CGSize
    let speed: Double
    let phase: Double
    let rotation: Double

    func position(in size: CGSize, time: TimeInterval) -> CGPoint {
        let x = (size.width * anchor.x) + CGFloat(sin((time * speed) + phase)) * orbit.width
        let y = (size.height * anchor.y) + CGFloat(cos((time * speed * 0.82) + (phase * 1.6))) * orbit.height
        return CGPoint(x: x, y: y)
    }

    func wobble(time: TimeInterval) -> CGSize {
        CGSize(
            width: 1.0 + CGFloat(sin((time * speed * 1.4) + phase) * 0.08),
            height: 1.0 + CGFloat(cos((time * speed * 1.2) + (phase * 1.2)) * 0.10)
        )
    }

    func rotationDrift(time: TimeInterval) -> Double {
        sin((time * speed * 8.0) + phase) * 10.0
    }
}

private struct MorphingBackdropBlob: Shape {
    var time: TimeInterval
    var phase: Double

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let count = 10
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadiusX = rect.width * 0.42
        let baseRadiusY = rect.height * 0.42

        let points = (0..<count).map { index -> CGPoint in
            let angle = (Double(index) / Double(count)) * .pi * 2.0
            let rippleA = sin((angle * 3.0) + (time * 0.42) + phase) * 0.15
            let rippleB = cos((angle * 5.0) - (time * 0.31) + (phase * 1.3)) * 0.08
            let rippleC = sin((angle * 2.0) + (time * 0.18) + (phase * 2.0)) * 0.06

            let radiusX = baseRadiusX * CGFloat(1.0 + rippleA + rippleB)
            let radiusY = baseRadiusY * CGFloat(1.0 + (rippleA * 0.7) - rippleC)

            return CGPoint(
                x: center.x + (CGFloat(cos(angle)) * radiusX),
                y: center.y + (CGFloat(sin(angle)) * radiusY)
            )
        }

        var path = Path()
        let firstMidpoint = midpoint(between: points[0], and: points[1])
        path.move(to: firstMidpoint)

        for index in 1..<count {
            let current = points[index]
            let next = points[(index + 1) % count]
            path.addQuadCurve(
                to: midpoint(between: current, and: next),
                control: current
            )
        }

        path.addQuadCurve(
            to: firstMidpoint,
            control: points[0]
        )

        path.closeSubpath()
        return path
    }

    private func midpoint(between first: CGPoint, and second: CGPoint) -> CGPoint {
        CGPoint(
            x: (first.x + second.x) * 0.5,
            y: (first.y + second.y) * 0.5
        )
    }
}
