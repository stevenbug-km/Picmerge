import SwiftUI

// MARK: - 裁剪按钮组
//
// 网页长图与本地拼接共用同一套 Photoshop 风格裁剪流程，
// 所以把「裁剪 / 确定裁剪 / 取消 / 清除裁剪」抽成一个小组件：
// 两边行为完全一致，日后要加按钮也只改这一处。
//
// 语义说明：
//   * 裁剪 / 继续裁剪：进入裁剪模式，出现待确认的裁剪框，但不改结果图。
//   * 确定裁剪：把草稿框应用到结果图（连续裁剪会自动做坐标复合）。
//   * 取消：放弃本次框选，已确认过的裁剪保留。
//   * 清除裁剪：恢复到未裁剪的整张图。

struct CropToolbar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            if state.isCropping {
                Button("确定裁剪") { state.confirmCrop() }
                    .buttonStyle(.borderedProminent)

                Button("取消") { state.cancelCropping() }
                    .buttonStyle(.bordered)
            } else {
                Button(state.hasCrop ? "继续裁剪" : "裁剪") {
                    state.toggleCropping()
                }
                .buttonStyle(.bordered)
                .disabled(!state.canCrop)
            }

            Button("清除裁剪") { state.clearCrop() }
                .buttonStyle(.bordered)
                .disabled(!state.hasCrop && !state.isCropping)
        }
    }
}
