import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - sRGB <-> Linear helpers

@inline(__always) func srgbToLinear(_ c: Double) -> Double {
    if c <= 0.04045 { return c / 12.92 }
    return pow((c + 0.055) / 1.055, 2.4)
}

@inline(__always) func linearToSrgb(_ c: Double) -> Double {
    if c <= 0.0031308 { return 12.92 * c }
    return 1.055 * pow(c, 1.0/2.4) - 0.055
}

// MARK: - OKLab/OKLCH conversions (Björn Ottosson)

struct OKLab { var L: Double; var a: Double; var b: Double }
struct OKLCH { var L: Double; var C: Double; var h: Double }

func rgbToOKLab(r: Double, g: Double, b: Double) -> OKLab {
    let rLin = srgbToLinear(r)
    let gLin = srgbToLinear(g)
    let bLin = srgbToLinear(b)

    let l = 0.4122214708*rLin + 0.5363325363*gLin + 0.0514459929*bLin
    let m = 0.2119034982*rLin + 0.6806995451*gLin + 0.1073969566*bLin
    let s = 0.0883024619*rLin + 0.2817188376*gLin + 0.6299787005*bLin

    let l_ = cbrt(l)
    let m_ = cbrt(m)
    let s_ = cbrt(s)

    let L = 0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_
    let A = 1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_
    let B = 0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_
    return OKLab(L: L, a: A, b: B)
}

func okLabToRGB(_ lab: OKLab) -> (r: Double, g: Double, b: Double) {
    let L = lab.L, aC = lab.a, bC = lab.b
    let l_ = L + 0.3963377774*aC + 0.2158037573*bC
    let m_ = L - 0.1055613458*aC - 0.0638541728*bC
    let s_ = L - 0.0894841775*aC - 1.2914855480*bC

    let l = l_*l_*l_
    let m = m_*m_*m_
    let s = s_*s_*s_

    var r = +4.0767416621*l - 3.3077115913*m + 0.2309699292*s
    var g = -1.2684380046*l + 2.6097574011*m - 0.3413193965*s
    var bOut = -0.0041960863*l - 0.7034186147*m + 1.7076147010*s

    r = linearToSrgb(r); g = linearToSrgb(g); bOut = linearToSrgb(bOut)
    return (r, g, bOut)
}

func okLabToOKLCH(_ lab: OKLab) -> OKLCH {
    let C = sqrt(lab.a*lab.a + lab.b*lab.b)
    var h = atan2(lab.b, lab.a) * 180.0 / .pi
    if h < 0 { h += 360 }
    return OKLCH(L: lab.L, C: C, h: h)
}

func oklchToOKLab(_ lch: OKLCH) -> OKLab {
    let hr = lch.h * .pi / 180.0
    let a = cos(hr) * lch.C
    let b = sin(hr) * lch.C
    return OKLab(L: lch.L, a: a, b: b)
}

// Convert OKLCH to Color (sRGB), reducing chroma if out of gamut
func oklchToSRGBClamped(_ lch: OKLCH) -> Color {
    var lch = lch
    for _ in 0..<12 {
        let rgb = okLabToRGB(oklchToOKLab(lch))
        if rgb.r.isFinite && rgb.g.isFinite && rgb.b.isFinite,
           rgb.r >= 0 && rgb.r <= 1 && rgb.g >= 0 && rgb.g <= 1 && rgb.b >= 0 && rgb.b <= 1 {
            return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        }
        lch.C *= 0.92 // gently reduce chroma until in-gamut
    }
    let rgb = okLabToRGB(oklchToOKLab(lch))
    let r = min(max(rgb.r, 0), 1), g = min(max(rgb.g, 0), 1), b = min(max(rgb.b, 0), 1)
    return Color(red: r, green: g, blue: b)
}

// MARK: - Color utilities

extension Color {
    func toHexString() -> String? {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
        #elseif canImport(AppKit)
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent*255), Int(rgb.greenComponent*255), Int(rgb.blueComponent*255))
        #else
        return nil
        #endif
    }
}
