import SwiftUI

struct HeaderMatchModifier: ViewModifier {
    let matchedNamespace: Namespace.ID?
    let currentId: UUID
    let transitionId: UUID?
    let isActive: Bool

    func body(content: Content) -> some View {
        if let ns = matchedNamespace, isActive, transitionId == currentId {
            content.matchedGeometryEffect(id: currentId, in: ns, isSource: false)
        } else {
            content
        }
    }
}

