import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var exportDocument = ConfigurationDocument()
    @State private var isExporting = false
    @State private var isImporting = false

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $model.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.clear)
        } detail: {
            ZStack {
                AppBackdrop()
                content
                    .padding(24)
            }
            .toolbar { toolbarContent }
            .sheet(isPresented: $model.isShowingMonitorEditor) {
                MonitorEditorView(
                    draft: Binding(
                        get: { model.monitorDraft },
                        set: { model.monitorDraft = $0 }
                    ),
                    onCancel: { model.dismissMonitorEditor() },
                    onSave: {
                        Task {
                            await model.saveMonitor()
                        }
                    }
                )
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "PulseBoard-Export"
            ) { result in
                if case .failure(let error) = result {
                    model.transientMessage = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        await model.importMonitors(from: url)
                    }
                case .failure(let error):
                    model.transientMessage = error.localizedDescription
                }
            }
            .alert(
                "PulseBoard",
                isPresented: Binding(
                    get: { model.transientMessage != nil },
                    set: { newValue in
                        if !newValue {
                            model.transientMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.transientMessage = nil
                }
            } message: {
                Text(model.transientMessage ?? "")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.openNewMonitor()
            } label: {
                Label("Add Monitor", systemImage: "plus")
            }
            .help("Add a new monitor")

            Button {
                Task {
                    await model.runAllNow()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh all monitors now")

            Button {
                Task {
                    await model.setPauseAllMonitoring(!model.settings.pauseAllMonitoring)
                }
            } label: {
                Label(model.settings.pauseAllMonitoring ? "Resume" : "Pause", systemImage: model.settings.pauseAllMonitoring ? "play.fill" : "pause.fill")
            }
            .help(model.settings.pauseAllMonitoring ? "Resume monitoring checks" : "Pause monitoring checks")

            Button {
                isImporting = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import monitors from a JSON file")

            Menu {
                Button("Export Configuration") {
                    Task {
                        exportDocument = await model.exportDocument()
                        isExporting = true
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export your current configuration")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedSection {
        case .dashboard:
            DashboardView()
        case .monitors:
            MonitorWorkspaceView()
        case .incidents:
            IncidentsView()
        case .settings:
            SettingsView()
        case .help:
            HelpView()
        }
    }
}
