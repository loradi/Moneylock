import SwiftUI

struct FeedbackView: View {
    let result: ValidationResult
    let isLast: Bool
    let onNext: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Label(
                result.isCorrect ? "¡Correcto!" : "Incorrecto",
                systemImage: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.title3.bold())
            .foregroundStyle(result.isCorrect ? .green : .red)

            if !result.isCorrect, !result.expected.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Respuesta correcta:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(result.expected)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if !result.explanation.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Explicación")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(result.explanation)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button(isLast ? "Completar lección" : "Siguiente ejercicio",
                   action: isLast ? onFinish : onNext)
                .buttonStyle(.borderedProminent)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(result.isCorrect ? Color.green.opacity(0.1)
                                       : Color.red.opacity(0.1))
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}