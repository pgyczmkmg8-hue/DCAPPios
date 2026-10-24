import SwiftUI
import UIKit

/// 종이 꽃가루(컨페티) 효과. trigger 값이 바뀔 때마다 한 번 뿌려요.
struct ConfettiView: UIViewRepresentable {
    var trigger: Int

    func makeUIView(context: Context) -> ConfettiUIView {
        let v = ConfettiUIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: ConfettiUIView, context: Context) {
        if trigger != context.coordinator.lastTrigger {
            context.coordinator.lastTrigger = trigger
            // 화면 크기가 정해진 뒤에 뿌리도록 한 박자 늦춤
            DispatchQueue.main.async { uiView.burst() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastTrigger = 0 }
}

final class ConfettiUIView: UIView {
    private let emitter = CAEmitterLayer()

    private static let colors: [UIColor] = [
        UIColor(red: 0.29, green: 0.33, blue: 0.64, alpha: 1),   // 남색
        .systemPink, .systemYellow, .systemTeal, .systemOrange, .systemGreen, .systemPurple
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        emitter.emitterShape = .line
        emitter.renderMode = .oldestLast
        emitter.birthRate = 0
        emitter.emitterCells = Self.makeCells()
        layer.addSublayer(emitter)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -12)   // 화면 위쪽 바깥에서 떨어지게
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
    }

    private var burstID = 0

    /// 누를 때마다 다시 뿌림. 연달아 눌러도 마지막으로 누른 때부터 1.4초 동안 계속 뿌려짐
    func burst() {
        burstID += 1
        let id = burstID
        if emitter.birthRate == 0 { emitter.beginTime = CACurrentMediaTime() }
        emitter.birthRate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.burstID == id else { return }   // 그 사이 또 눌렀으면 멈추지 않음
            self.emitter.birthRate = 0     // 뿌리기만 멈추고, 이미 떨어지는 종이는 끝까지 보임
        }
    }

    private static func makeCells() -> [CAEmitterCell] {
        var cells: [CAEmitterCell] = []
        for color in colors {
            for shape in 0..<2 {   // 직사각형 종이 + 동그라미 종이
                let cell = CAEmitterCell()
                cell.contents = piece(color: color, round: shape == 1).cgImage
                cell.birthRate = 7
                cell.lifetime = 7
                cell.velocity = 170
                cell.velocityRange = 90
                cell.emissionLongitude = .pi            // 아래쪽으로
                cell.emissionRange = .pi / 4
                cell.yAcceleration = 160                // 중력
                cell.xAcceleration = 0
                cell.spin = 3
                cell.spinRange = 5
                cell.scale = 0.7
                cell.scaleRange = 0.35
                cell.alphaSpeed = -0.08
                cells.append(cell)
            }
        }
        return cells
    }

    private static func piece(color: UIColor, round: Bool) -> UIImage {
        let size = round ? CGSize(width: 9, height: 9) : CGSize(width: 8, height: 14)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            let rect = CGRect(origin: .zero, size: size)
            if round {
                ctx.cgContext.fillEllipse(in: rect)
            } else {
                UIBezierPath(roundedRect: rect, cornerRadius: 1.5).fill()
            }
        }
    }
}
