import SwiftUI

struct HelpView: View {
    @State private var expandedSectionIDs: Set<String> = ["settings"]
    @State private var expandedSubsectionIDs: Set<String> = []

    private let maxContentWidth: CGFloat = 980
    private let sections = HelpContent.sections

    var body: some View {
        ZStack {
            AppBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    ForEach(sections) { section in
                        GlassCard {
                            DisclosureGroup(isExpanded: binding(forSectionID: section.id)) {
                                VStack(alignment: .leading, spacing: 18) {
                                    Text(section.summary)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(Array(section.highlights.enumerated()), id: \.offset) { _, highlight in
                                            Label(highlight, systemImage: "checkmark.circle.fill")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Divider()

                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(section.subsections) { subsection in
                                            subsectionDisclosure(subsection)
                                        }
                                    }
                                }
                                .padding(.top, 16)
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    Label(section.title, systemImage: section.systemImage)
                                        .font(.title3.weight(.semibold))
                                    Spacer()
                                    Text("\(section.subsections.count) topics")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.accentColor)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Help")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Start with Settings. This help center is structured to grow alongside the main sidebar sections with expandable topics and task-focused guidance.")
                .foregroundStyle(.secondary)
        }
    }

    private func subsectionDisclosure(_ subsection: HelpSubsectionContent) -> some View {
        DisclosureGroup(isExpanded: binding(forSubsectionID: subsection.id)) {
            VStack(alignment: .leading, spacing: 14) {
                Text(subsection.intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(subsection.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        Text(item.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if item.id != subsection.items.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(subsection.title)
                    .font(.headline)
                Spacer()
                Text("\(subsection.items.count) items")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.accentColor)
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06))
        )
    }

    private func binding(forSectionID id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSectionIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSectionIDs.insert(id)
                } else {
                    expandedSectionIDs.remove(id)
                }
            }
        )
    }

    private func binding(forSubsectionID id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSubsectionIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSubsectionIDs.insert(id)
                } else {
                    expandedSubsectionIDs.remove(id)
                }
            }
        )
    }
}