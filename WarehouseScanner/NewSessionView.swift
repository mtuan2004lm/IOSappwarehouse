import SwiftUI

/// Tạo phiên mới (giống nút "Bắt đầu phiên mới" trên web): chọn đơn vị vận chuyển, cửa kho, người giao, biển số, số kiện.
struct NewSessionView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var onCreated: (ReceivingSession) -> Void

    static let carriers = ["Amazon Logistics", "Amazon Package", "Amazon Pallet", "DHL", "FEDEX EXPRESS", "FEDEX GROUND", "FedEx", "Other", "UPS", "USPS"]

    @State private var carrier = "DHL"
    @State private var gate = "OR_1 - D2"
    @State private var driver = ""
    @State private var plate = ""
    @State private var expected = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section(tr("Đơn vị vận chuyển")) {
                Picker(tr("Đơn vị vận chuyển"), selection: $carrier) {
                    ForEach(Self.carriers, id: \.self) { Text($0).tag($0) }
                }
            }
            Section(tr("Thông tin chuyến")) {
                TextField(tr("Cửa kho"), text: $gate).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField(tr("Người giao"), text: $driver)
                TextField(tr("Biển số xe"), text: $plate).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField(tr("Số kiện của phiên (nhập tay)"), text: $expected).keyboardType(.numberPad)
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent).font(.footnote) }
            }
            Section {
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView() }
                        Text(saving ? tr("Đang tạo…") : tr("Bắt đầu quét")).font(.headline)
                        Spacer()
                    }
                }
                .disabled(saving)
            } footer: { Text(tr("Có thể sửa lại số kiện khi đang quét trên web.")) }
        }
        .navigationTitle(tr("Bắt đầu phiên mới"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Huỷ")) { dismiss() } } }
    }

    private func create() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            let s = try await store.api.createSession(carrier: carrier, gate: gate, driver: driver, plate: plate,
                                                      expected: Int(expected.trimmingCharacters(in: .whitespaces)) ?? 0)
            Haptics.success()
            dismiss()
            onCreated(s)
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}
