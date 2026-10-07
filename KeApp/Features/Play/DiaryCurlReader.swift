import SwiftUI
import UIKit

/// A real UIKit paper curl. Date binding changes only after a completed turn.
struct DiaryCurlReader: UIViewControllerRepresentable {
    @Binding var date: Date
    let pages: [KeDiaryPage]
    let theme: Theme
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: reduceMotion ? .scroll : .pageCurl, navigationOrientation: .horizontal)
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.isDoubleSided = false
        controller.view.backgroundColor = UIColor(theme.pageBackground)
        controller.setViewControllers([context.coordinator.page(date)], direction: .forward, animated: false)
        return controller
    }
    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard !coordinator.turning else { return }
        if let current = controller.viewControllers?.first as? DiaryPageController,
           CompanionDate.calendar.isDate(current.date, inSameDayAs: date) {
            current.rootView = coordinator.paper(date)
        } else {
            controller.setViewControllers([coordinator.page(date)], direction: .forward, animated: false)
        }
    }
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: DiaryCurlReader
        var turning = false
        init(_ parent: DiaryCurlReader) { self.parent = parent }
        func paper(_ date: Date) -> DiaryPaperPage {
            DiaryPaperPage(date: date, entry: parent.pages.first { CompanionDate.calendar.isDate($0.date, inSameDayAs: date) }, theme: parent.theme)
        }
        func page(_ date: Date) -> DiaryPageController {
            let page = DiaryPageController(date: date, rootView: paper(date))
            page.view.backgroundColor = UIColor(parent.theme.pageBackground)
            return page
        }
        func pageViewController(_ controller: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            neighbor(viewController, offset: -1)
        }
        func pageViewController(_ controller: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            neighbor(viewController, offset: 1)
        }
        private func neighbor(_ controller: UIViewController, offset: Int) -> UIViewController? {
            guard let current = controller as? DiaryPageController,
                  let date = CompanionDate.calendar.date(byAdding: .day, value: offset, to: current.date),
                  date <= Date() else { return nil }
            return page(date)
        }
        func pageViewController(_ controller: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { turning = true }
        func pageViewController(_ controller: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            turning = false
            if completed, let current = controller.viewControllers?.first as? DiaryPageController {
                parent.date = current.date
            } else {
                // A cancelled finger drag must not change the selected date.
                if let current = controller.viewControllers?.first as? DiaryPageController { parent.date = current.date }
            }
        }
    }
}

final class DiaryPageController: UIHostingController<DiaryPaperPage> {
    let date: Date
    init(date: Date, rootView: DiaryPaperPage) { self.date = date; super.init(rootView: rootView) }
    @MainActor required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}

struct DiaryPaperPage: View {
    let date: Date
    let entry: KeDiaryPage?
    @ObservedObject var theme: Theme
    private var dayLabel: String {
        let f = DateFormatter(); f.calendar = CompanionDate.calendar; f.timeZone = CompanionDate.calendar.timeZone
        f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy年M月d日"; return f.string(from: date)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("dear diary").font(Moonlight.script(30)).foregroundStyle(theme.pageAccent)
                Text(dayLabel).font(Moonlight.serif(12)).foregroundStyle(theme.pageColor.textSecondary)
                    .accessibilityIdentifier("diary-page-date")
                Rectangle().fill(theme.pageColor.separator).frame(height: 0.5)
                if let entry {
                    Text(entry.title).font(Moonlight.serif(21))
                    Text(entry.content).font(Moonlight.serif(16)).lineSpacing(9).textSelection(.enabled)
                        .accessibilityIdentifier("diary-page-content")
                } else {
                    Text("这一天还没有公开的日记。").font(Moonlight.serif(16)).foregroundStyle(theme.pageColor.textSecondary)
                        .padding(.top, 20)
                }
                Text("柯").font(Moonlight.serif(16)).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 15)
            }.padding(.horizontal, 19).padding(.vertical, 25)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.background(theme.skin == .day ? Moonlight.pearl : theme.pageColor.card)
            .foregroundStyle(theme.pageColor.textPrimary)
            .accessibilityIdentifier("diary-paper-page")
    }
}
