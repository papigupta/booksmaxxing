import Foundation

struct LabPoint { var L: Double; var a: Double; var b: Double }

struct ClusterResult { let centroid: LabPoint; let population: Int }

struct KMeansQuantizer {
    static func quantize(labPoints: [LabPoint], k: Int = 5, maxIterations: Int = 12) -> [ClusterResult] {
        guard !labPoints.isEmpty, k > 0 else { return [] }
        let k = min(k, labPoints.count)

        // k-means++ seeding
        var centroids = [LabPoint]()
        centroids.append(labPoints.randomElement()!)
        while centroids.count < k {
            var distances = [Double](repeating: 0, count: labPoints.count)
            for (i, p) in labPoints.enumerated() {
                var d2 = Double.greatestFiniteMagnitude
                for c in centroids {
                    let dl = p.L - c.L, da = p.a - c.a, db = p.b - c.b
                    let dist = dl*dl + da*da + db*db
                    if dist < d2 { d2 = dist }
                }
                distances[i] = d2
            }
            let total = distances.reduce(0, +)
            if total == 0 { break }
            let r = Double.random(in: 0..<total)
            var acc = 0.0
            var chosen = 0
            for (i, d) in distances.enumerated() {
                acc += d
                if acc >= r { chosen = i; break }
            }
            centroids.append(labPoints[chosen])
        }

        // Lloyd iterations
        var assignments = [Int](repeating: 0, count: labPoints.count)
        for _ in 0..<maxIterations {
            // Assign
            for (i, p) in labPoints.enumerated() {
                var best = 0
                var bestDist = Double.greatestFiniteMagnitude
                for (j, c) in centroids.enumerated() {
                    let dl = p.L - c.L, da = p.a - c.a, db = p.b - c.b
                    let d = dl*dl + da*da + db*db
                    if d < bestDist { bestDist = d; best = j }
                }
                assignments[i] = best
            }
            // Update
            var sums = Array(repeating: (L: 0.0, a: 0.0, b: 0.0, n: 0), count: centroids.count)
            for (i, p) in labPoints.enumerated() {
                let g = assignments[i]
                sums[g].L += p.L; sums[g].a += p.a; sums[g].b += p.b; sums[g].n += 1
            }
            for j in 0..<centroids.count {
                if sums[j].n > 0 {
                    centroids[j] = LabPoint(L: sums[j].L/Double(sums[j].n), a: sums[j].a/Double(sums[j].n), b: sums[j].b/Double(sums[j].n))
                }
            }
        }

        // Build results
        var counts = Array(repeating: 0, count: centroids.count)
        for g in assignments { counts[g] += 1 }
        return zip(centroids, counts).map { ClusterResult(centroid: $0.0, population: $0.1) }
            .sorted { $0.population > $1.population }
    }
}

