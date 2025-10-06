import SwiftUI

enum ExperimentsPaletteStore {
    static let defaultMonochromeRoles: [PaletteRole] = PaletteGenerator.generateMonochromeRoles()
    static let defaultMonochromeJSON: String = PaletteGenerator.serializeRolesToJSON(defaultMonochromeRoles)
}
