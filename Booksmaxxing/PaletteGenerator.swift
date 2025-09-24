import SwiftUI

struct PaletteRole {
    let name: String
    let tones: [(tone: Int, color: Color)]
}

struct SeedColor { let color: Color; let population: Int; let lch: OKLCH }

struct PaletteGenerator {
    // Score by population x chroma^gamma
    static func scoreSeeds(_ clusters: [ClusterResult]) -> [SeedColor] {
        let total = max(1, clusters.map { $0.population }.reduce(0, +))
        return clusters.map { c in
            let lab = OKLab(L: c.centroid.L, a: c.centroid.a, b: c.centroid.b)
            var lch = okLabToOKLCH(lab)
            // Avoid extremely low chroma and extremes
            if lch.C < 0.02 { lch.C = 0.02 }
            let pop = Double(c.population) / Double(total)
            let score = pop * pow(lch.C, 1.2)
            let color = oklchToSRGBClamped(lch)
            return (score, SeedColor(color: color, population: c.population, lch: lch))
        }
        .sorted { $0.0 > $1.0 }
        .map { $0.1 }
    }

    static func generateRoles(from seeds: [SeedColor]) -> [PaletteRole] {
        guard let primarySeed = seeds.first else { return [] }
        let secondSeed = seeds.dropFirst().first ?? primarySeed

        func tones(for base: OKLCH, chroma: Double, name: String, toneStops: [Int]) -> PaletteRole {
            let arr: [(Int, Color)] = toneStops.map { t in
                let l = Double(t) / 100.0
                let c = chroma
                let color = oklchToSRGBClamped(OKLCH(L: l, C: c, h: base.h))
                return (t, color)
            }
            return PaletteRole(name: name, tones: arr)
        }

        // Role chroma targets (rough Material You feel)
        let primary = tones(for: primarySeed.lch, chroma: min(max(primarySeed.lch.C, 0.06), 0.12), name: "Primary", toneStops: [95,90,80,70,60,50,40,30])
        let secondary = tones(for: OKLCH(L: primarySeed.lch.L, C: min(primarySeed.lch.C*0.6, 0.08), h: primarySeed.lch.h), chroma: min(primarySeed.lch.C*0.6, 0.08), name: "Secondary", toneStops: [95,90,80,70,60,50,40,30])
        let tertiaryBaseHue = secondSeed.lch.h
        let tertiary = tones(for: OKLCH(L: secondSeed.lch.L, C: min(max(secondSeed.lch.C, 0.06), 0.12), h: tertiaryBaseHue), chroma: min(max(secondSeed.lch.C, 0.06), 0.12), name: "Tertiary", toneStops: [95,90,80,70,60,50,40,30])
        let neutral = tones(for: OKLCH(L: primarySeed.lch.L, C: 0.02, h: primarySeed.lch.h), chroma: 0.02, name: "Neutral", toneStops: [98,96,94,92,90,80,70,60,50,40,30])
        let neutralVariant = tones(for: OKLCH(L: primarySeed.lch.L, C: 0.035, h: primarySeed.lch.h), chroma: 0.035, name: "Neutral Variant", toneStops: [98,96,94,92,90,80,70,60,50,40,30])

        return [primary, secondary, tertiary, neutral, neutralVariant]
    }
}

