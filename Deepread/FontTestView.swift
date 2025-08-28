import SwiftUI

struct FontTestView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Debug: Check if font files exist in bundle
                Text("Font file exists: \(checkFontFile())")
                    .font(.caption)
                    .foregroundColor(.red)
                
                Text("System Font")
                    .font(.system(size: 24))
                
                Text("Fraunces Regular")
                    .font(.custom("Fraunces", size: 24))
                
                Text("Fraunces Light")
                    .font(.custom("Fraunces", size: 24))
                    .fontWeight(.light)
                
                Text("Fraunces Medium")
                    .font(.custom("Fraunces", size: 24))
                    .fontWeight(.medium)
                
                Text("Fraunces Semibold")
                    .font(.custom("Fraunces", size: 24))
                    .fontWeight(.semibold)
                
                Text("Fraunces Bold")
                    .font(.custom("Fraunces", size: 24))
                    .fontWeight(.bold)
                
                Text("Fraunces Black")
                    .font(.custom("Fraunces", size: 24))
                    .fontWeight(.black)
                
                Divider()
                
                Text("All Available Font Families:")
                    .font(.headline)
                
                // List ALL font families to debug
                ForEach(UIFont.familyNames.sorted(), id: \.self) { family in
                    VStack(alignment: .leading) {
                        Text("Family: \(family)")
                            .font(.caption)
                            .foregroundColor(.blue)
                        ForEach(UIFont.fontNames(forFamilyName: family), id: \.self) { name in
                            Text(name)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Specifically check for Fraunces
                Text("Fraunces fonts found: \(UIFont.familyNames.filter { $0.lowercased().contains("fraun") }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.yellow.opacity(0.2))
            }
            .padding()
        }
    }
    
    func checkFontFile() -> String {
        if let fontURL = Bundle.main.url(forResource: "Fraunces-Variable", withExtension: "ttf") {
            return "YES - Found at: \(fontURL.lastPathComponent)"
        } else if Bundle.main.url(forResource: "Fonts/Fraunces-Variable", withExtension: "ttf") != nil {
            return "YES - Found with Fonts path"
        } else {
            // List all TTF files in bundle
            let ttfFiles = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
            if ttfFiles.isEmpty {
                return "NO - No TTF files in bundle!"
            } else {
                return "NO - But found: \(ttfFiles.map { $0.lastPathComponent }.joined(separator: ", "))"
            }
        }
    }
}

#Preview {
    FontTestView()
}