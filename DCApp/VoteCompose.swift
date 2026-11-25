import SwiftUI
import PhotosUI
import UIKit

// MARK: - 투표 만들기 (앱 화면)
//
// 디시 투표 창 대신 앱 화면에서 쓴다. 등록은 디시 투표 폼의 칸(보기·보기 사진·기간·결과 공개·권한)에
// 같은 값을 채워 디시 함수(vote_submit)로 만든다. 사진은 디시 투표 사진 올리기(uploadVote)로 올린다.

/// 보기 사진 한 장 (GIF는 원본, 그 밖은 JPEG로 줄여서)
struct VoteImageData {
    let data: Data
    let mime: String
    let ext: String
    let preview: UIImage
}

/// 등록할 보기 한 칸
struct VoteSubmitOption {
    let text: String
    let image: VoteImageData?
}

/// 보기 입력 칸 (화면에서만 씀)
private struct VoteOptionDraft: Identifiable {
    let id = UUID()
    var text = ""
    var image: VoteImageData?
}

struct VoteComposeSheet: View {
    let model: WebViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var options: [VoteOptionDraft] = [VoteOptionDraft(), VoteOptionDraft()]
    @State private var multi = false
    @State private var multiCount = 2
    @State private var endEnabled = true
    @State private var endDate = VoteComposeSheet.defaultEnd()
    @State private var showResultBeforeEnd = true
    @State private var permission = "A"            // A: 모두(유동 포함) · M: 고정닉만
    @State private var submitting = false

    private static let maxOptions = 20
    private static let minLeadMinutes: TimeInterval = 10 * 60

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var endIsValid: Bool { endDate.timeIntervalSinceNow >= Self.minLeadMinutes }
    private var canSubmit: Bool {
        !trimmedTitle.isEmpty && trimmedTitle.count <= 40
            && options.count >= 2 && options.count <= Self.maxOptions
            && options.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 30 }
            && (!multi || (2...max(2, options.count)).contains(multiCount))
            && (!endEnabled || endIsValid)
            && !submitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("투표 제목 (40자 이내)", text: $title)
                } header: {
                    Text("제목")
                }

                Section {
                    ForEach($options) { $option in
                        optionRow($option)
                    }
                    .onDelete { offsets in
                        if options.count - offsets.count >= 2 { options.remove(atOffsets: offsets) }
                    }
                    if options.count < Self.maxOptions {
                        Button {
                            options.append(VoteOptionDraft())
                        } label: {
                            Label("보기 추가", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    Text("보기")
                } footer: {
                    Text("보기는 2개 이상 필요해요. 보기는 왼쪽으로 밀면 지울 수 있어요. 사진은 보기마다 한 장씩 넣을 수 있어요.")
                }

                Section {
                    Toggle("복수 선택 사용", isOn: $multi)
                    if multi {
                        Stepper("최대 \(min(multiCount, options.count))개까지 고르기",
                                value: $multiCount, in: 2...max(2, options.count))
                    }
                } header: {
                    Text("선택 방식")
                }

                Section {
                    Toggle("종료 시간 설정", isOn: $endEnabled)
                    if endEnabled {
                        DatePicker("종료 시간", selection: $endDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                } header: {
                    Text("투표 기간")
                } footer: {
                    Text(endEnabled
                         ? (endIsValid ? "종료 시간은 10분 단위로 맞춰져요." : "종료 시간은 지금부터 10분 이후여야 해요.")
                         : "끄면 작성자가 투표를 종료할 때까지 계속돼요.")
                }

                Section {
                    Toggle("종료 전 결과 미리보기", isOn: $showResultBeforeEnd)
                } header: {
                    Text("결과 공개")
                } footer: {
                    Text("켜 두면 투표가 끝나기 전에도 결과를 볼 수 있어요.")
                }

                Section {
                    Picker("투표 권한", selection: $permission) {
                        Text("모두 (유동 포함)").tag("A")
                        Text("고정닉만").tag("M")
                    }
                } header: {
                    Text("투표 권한")
                } footer: {
                    Text("디시 투표 권한은 '모두'와 '고정닉만' 두 가지예요.")
                }
            }
            .navigationTitle("투표 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("만들기") { submit() }
                            .disabled(!canSubmit)
                            .fontWeight(.semibold)
                    }
                }
            }
            .tint(DCTheme.accent)
        }
        .sheetUnderBlueBar(medium: false)
    }

    /// 보기 한 줄: 글자 칸 + 사진 고르기 (+ 고른 사진 미리보기와 지우기)
    @ViewBuilder
    private func optionRow(_ option: Binding<VoteOptionDraft>) -> some View {
        HStack(spacing: 8) {
            TextField("보기 (30자 이내)", text: option.text)
            if let preview = option.wrappedValue.image?.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Button {
                    option.wrappedValue.image = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("보기 사진 지우기")
            }
            PhotosPicker(selection: pickerBinding(for: option.wrappedValue.id), matching: .images) {
                Image(systemName: option.wrappedValue.image == nil ? "photo" : "photo.fill")
                    .foregroundStyle(DCTheme.accent)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("보기 사진 고르기")
        }
    }

    /// 사진을 고르면 그 보기 칸에 넣음 (고른 항목은 바로 비워서 같은 사진을 다시 고를 수 있게)
    private func pickerBinding(for id: UUID) -> Binding<PhotosPickerItem?> {
        Binding(
            get: { nil },
            set: { item in
                guard let item else { return }
                Task {
                    guard let raw = try? await item.loadTransferable(type: Data.self),
                          let prepared = Self.prepareImage(raw),
                          let index = options.firstIndex(where: { $0.id == id }) else { return }
                    options[index].image = prepared
                }
            })
    }

    /// 사진 준비: GIF는 그대로, 나머지는 긴 쪽 1600px 이하 JPEG로
    private static func prepareImage(_ raw: Data) -> VoteImageData? {
        guard let image = UIImage(data: raw) else { return nil }
        if DeferredImages.sniffImage(raw) == "image/gif" {
            return VoteImageData(data: raw, mime: "image/gif", ext: "gif", preview: image)
        }
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longSide, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let jpeg = renderer.jpegData(withCompressionQuality: 0.85) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let shown = UIImage(data: jpeg) else { return nil }
        return VoteImageData(data: jpeg, mime: "image/jpeg", ext: "jpg", preview: shown)
    }

    /// 기본 종료 시간: 지금부터 한 시간 뒤를 10분 단위로 올림
    private static func defaultEnd() -> Date {
        let base = Date().addingTimeInterval(3600)
        let cal = Calendar.current
        let minute = cal.component(.minute, from: base)
        let rounded = ((minute + 9) / 10) * 10
        return cal.date(byAdding: .minute, value: rounded - minute, to: base) ?? base
    }

    /// 디시 투표 폼의 날짜·시·분 칸 값 (시는 01~24시, 0시는 전날의 24시로 씀)
    static func dcEnd(_ date: Date) -> (date: String, hour: String, minute: String) {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = comps.minute ?? 0
        var when = date
        if minute % 10 != 0 {
            let up = ((minute + 9) / 10) * 10
            when = cal.date(byAdding: .minute, value: up - minute, to: date) ?? date
            comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        }
        var hour = comps.hour ?? 0
        if hour == 0 {
            when = cal.date(byAdding: .day, value: -1, to: when) ?? when
            comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: when)
            hour = 24
        }
        let day = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        return (day, String(format: "%02d", hour), String(format: "%02d", (comps.minute ?? 0)))
    }

    private func submit() {
        guard canSubmit else { return }
        submitting = true
        let list = options.map { VoteSubmitOption(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), image: $0.image) }
        let end = Self.dcEnd(endDate)
        let t = trimmedTitle
        let isMulti = multi
        let count = min(multiCount, list.count)
        let endOn = endEnabled
        let preview = showResultBeforeEnd
        let perm = permission
        Task {
            let result = await model.submitVote(title: t, options: list, multi: isMulti, multiCount: count,
                                                endDate: endOn, date: end.date, hour: end.hour, minute: end.minute,
                                                preview: preview, permission: perm)
            submitting = false
            if result == "ok" { dismiss() }
        }
    }
}
