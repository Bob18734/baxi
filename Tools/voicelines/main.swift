// Prints every line Baxi can say on the practice routes, at every experience level, as JSON
// {"<key>": "<line>"}, for scripts/build_voice.py to record.
//
//   swift run baxi-voicelines > /tmp/lines.json
@testable import Baxi
import Foundation

let cache = try BundledData.carmelCache()
let features = FeatureExtractor.extract(from: cache)
let hin = try? BundledData.highInjuryNetwork()
var all = VoiceLines.fixed
for p in RouteService.presets {
    let route = try RouteService.preset(p.id)
    let prep = RoutePrep.make(route: route, cache: cache, features: features, highInjury: hin)
    for level in ExperienceLevel.allCases { all.formUnion(VoiceLines.lines(route: route, prep: prep, level: level)) }
}
let byKey = Dictionary(uniqueKeysWithValues: all.map { (VoiceLines.key($0), $0) })
let data = try JSONSerialization.data(withJSONObject: byKey, options: [.sortedKeys, .prettyPrinted])
FileHandle.standardOutput.write(data)
