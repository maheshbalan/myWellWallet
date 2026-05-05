import Foundation
import HealthKit
import Flutter

/// Syncs Clinical Health Records lab results (FHIR) from Apple Health into the app DB via Dart.
/// Requires Runner.entitlements `health-records` (already configured).
final class ClinicalHealthRecordsPlugin {
    static let channelName = "com.mywellwallet/clinical_lab_results"
    private static var didRegister = false

    /// One store per process; avoids extra HKHealthStore() instances beside other plugins.
    private static let healthStore = HKHealthStore()

    static func register(messenger: FlutterBinaryMessenger) {
        guard !didRegister else { return }
        didRegister = true

        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        let plugin = ClinicalHealthRecordsPlugin()

        channel.setMethodCallHandler { call, result in
            DispatchQueue.main.async {
                plugin.handle(call: call, result: result)
            }
        }
    }

    /// Clinical Health Records queries are unsupported on Simulator and flaky without Health data.
    private static func healthRecordsLikelySupported() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if #available(iOS 11.0, *) {
            return NSClassFromString("HKClinicalRecord") != nil
        }
        return false
        #endif
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isHealthRecordsAvailable":
            result(Self.healthRecordsLikelySupported())
        case "requestAuthorization":
            requestAuthorization(result: result)
        case "syncLabResults":
            let args = call.arguments as? [String: Any]
            let days = (args?["days"] as? NSNumber)?.intValue ?? 730
            syncLabResults(lookbackDays: days, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func requestAuthorization(result: @escaping FlutterResult) {
        guard let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) else {
            result(false)
            return }
        guard Self.healthRecordsLikelySupported() else {
            result(false)
            return
        }

        // Read-only clinical access: pass `nil` for toShare. An empty Set can misbehave on some iOS builds.
        Self.healthStore.requestAuthorization(toShare: nil, read: Set([clinicalType])) { ok, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "auth_error",
                                        message: error.localizedDescription,
                                        details: nil))
                } else {
                    result(ok)
                }
            }
        }
    }

    /// Returns list of NSDictionary rows for Dart (`insertHealthLabResults`).
    private func syncLabResults(lookbackDays: Int, result: @escaping FlutterResult) {
        guard let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) else {
            result([])
            return
        }
        guard Self.healthRecordsLikelySupported() else {
            result([])
            return
        }

        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -max(lookbackDays, 1), to: end) else {
            result([])
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        // Cap batches to reduce memory spikes when transmitting large payloads over the platform channel.
        let clinicalBatchLimit = 3500

        let query = HKSampleQuery(
            sampleType: clinicalType,
            predicate: predicate,
            limit: clinicalBatchLimit,
            sortDescriptors: [sort]
        ) { _, samples, error in

            if let error = error {
                DispatchQueue.main.async {
                    result(FlutterError(code: "query_error",
                                        message: error.localizedDescription,
                                        details: nil))
                }
                return
            }

            let records = samples as? [HKClinicalRecord] ?? []
            var payload: [[String: Any]] = []

            autoreleasepool {
                for record in records {
                    let bundleId = record.sourceRevision.source.bundleIdentifier ?? ""
                    let sourceDisplay = Self.safeDisplayName(for: record)
                    let sourceName = record.sourceRevision.source.name ?? sourceDisplay
                    let specimen = ""

                    guard let obsList = Self.extractObservationDicts(record: record) else { continue }

                    for obsDict in obsList {
                        let rows = Self.rowsFromObservation(
                            obsDict,
                            clinicRecordId: record.uuid.uuidString,
                            sourceBundleId: bundleId,
                            sourceName: sourceName,
                            specimenType: specimen
                        )
                        payload.append(contentsOf: rows)
                    }
                }
            }

            DispatchQueue.main.async {
                result(payload)
            }
        }

        Self.healthStore.execute(query)
    }

    private static func safeDisplayName(for record: HKClinicalRecord) -> String {
        let dn = record.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return dn.isEmpty ? "Clinical record" : dn
    }

    /// Pull FHIR JSON from HKClinicalRecord and walk Bundle / DiagnosticReport / Observation.
    private static func extractObservationDicts(record: HKClinicalRecord) -> [[String: Any]]? {
        guard let fh = record.fhirResource else { return nil }
        let raw = fh.data
        guard !raw.isEmpty else { return nil }

        guard
            let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else {
            return nil
        }

        var observations: [[String: Any]] = []
        accumulateObservations(from: root, into: &observations)
        return observations
    }

    private static func accumulateObservations(from resource: [String: Any],
                                                 into observations: inout [[String: Any]]) {
        if let rt = resource["resourceType"] as? String {
            switch rt {
            case "Observation":
                observations.append(resource)
                return
            case "DiagnosticReport":
                if let contained = resource["contained"] as? [[String: Any]] {
                    for c in contained {
                        accumulateObservations(from: c, into: &observations)
                    }
                }
                return
            case "Bundle":
                if let entries = resource["entry"] as? [[String: Any]] {
                    for entry in entries {
                        if let r = entry["resource"] as? [String: Any] {
                            accumulateObservations(from: r, into: &observations)
                        }
                    }
                }
                return
            default:
                return
            }
        }
    }

    /// One HKClinical FHIR Observation (or flattened component rows) → app DB rows.
    private static func rowsFromObservation(_ obs: [String: Any],
                                              clinicRecordId: String,
                                              sourceBundleId: String,
                                              sourceName: String,
                                              specimenType: String) -> [[String: Any]] {
        if let comps = obs["component"] as? [[String: Any]], !comps.isEmpty {
            return comps.enumerated().compactMap { idx, comp in
                mergedComponentRow(obs,
                                   compIndex: idx,
                                   component: comp,
                                   clinicRecordId: clinicRecordId,
                                   sourceBundleId: sourceBundleId,
                                   sourceName: sourceName,
                                   specimenType: specimenType)
            }
        }
        if let row = singleObservationRow(obs,
                                          clinicRecordId: clinicRecordId,
                                           componentSuffix: "",
                                          sourceBundleId: sourceBundleId,
                                          sourceName: sourceName,
                                          specimenType: specimenType) {
            return [row]
        }
        return []
    }

    private static func mergedComponentRow(_ parent: [String: Any],
                                          compIndex: Int,
                                           component: [String: Any],
                                          clinicRecordId: String,
                                          sourceBundleId: String,
                                           sourceName: String,
                                           specimenType: String) -> [String: Any]? {
        var merged: [String: Any] = parent
        merged["code"] = component["code"] ?? parent["code"]

        merged["valueQuantity"] = component["valueQuantity"] ?? merged["valueQuantity"]
        merged["valueString"] = component["valueString"] ?? merged["valueString"]
        merged["valueCodeableConcept"] = component["valueCodeableConcept"]
        merged["interpretation"] = component["interpretation"] ?? merged["interpretation"]
        merged["referenceRange"] = component["referenceRange"] ?? merged["referenceRange"]

        merged.removeValue(forKey: "component")
        merged.removeValue(forKey: "contained")

        return singleObservationRow(merged,
                                    clinicRecordId: clinicRecordId,
                                    componentSuffix: "_c\(compIndex)",
                                    sourceBundleId: sourceBundleId,
                                    sourceName: sourceName,
                                    specimenType: specimenType)
    }

    /// Single Observation → one DB dictionary.
    private static func singleObservationRow(_ obs: [String: Any],
                                             clinicRecordId: String,
                                               componentSuffix: String,
                                               sourceBundleId: String,
                                             sourceName: String,
                                             specimenType: String) -> [String: Any]? {
        let (name, loinc) = codeBundle(from: obs["code"])

        guard name != "" || loinc != "" else {
            return nil }

        let (valueNum, valueStr, unit) = quantityAndString(from: obs)
        guard valueNum != nil || (valueStr != nil && !valueStr!.isEmpty) else {
            return nil }

        let (refLow, refHigh, refText) = referenceRangeTriple(from: obs["referenceRange"])
        let recorded = observationDate(obs)
        let id = "\(clinicRecordId)\(componentSuffix)_\(suffixFromCode(loinc: loinc ?? "", name: name))"

        return [
            "id": id,
            "name": name.isEmpty ? (loinc ?? "Lab result") : name,
            "loinc_code": loinc,
            "value_numeric": valueNum,
            "value_string": valueStr,
            "unit": unit,
            "reference_range_low": refLow,
            "reference_range_high": refHigh,
            "reference_range_text": refText,
            "source_name": sourceName,
            "source_bundle_id": sourceBundleId,
            "specimen_type": specimenType,
            "recorded_at": ISO8601DateFormatter().string(from: recorded),
        ]
    }

    /// Stable alphanumeric suffix for row id uniqueness (SQLite primary key length limit is fine).
    private static func suffixFromCode(loinc: String, name: String) -> String {
        let base = "\(loinc)_\(name)".lowercased()
        let cleaned = base.map { c -> Character in
            guard let u = c.unicodeScalars.first else { return "_" }
            if CharacterSet.alphanumerics.contains(u) { return c }
            if c == "-" || c == "." { return c }
            return "_"
        }
        var s = String(cleaned)
        while s.contains("__") {
            s = s.replacingOccurrences(of: "__", with: "_")
        }
        if s.isEmpty { return "lab" }
        return String(s.prefix(72))
    }

    /// Best-effort: code.display + optional LOINC.
    private static func codeBundle(from codeField: Any?) -> (display: String, loinc: String?) {
        guard let dict = codeField as? [String: Any] else { return ("", nil) }

        let text = dict["text"] as? String
        var display = ""

        var loinc: String?

        if let coding = dict["coding"] as? [[String: Any]] {
            for c in coding {
                let system = (c["system"] as? String ?? "").lowercased()
                if system.contains("loinc"), let cc = c["code"] as? String {
                    loinc = cc
                }
                if display.isEmpty {
                    display = (c["display"] as? String) ?? ""
                }
            }
        }

        let name = !(text ?? "").isEmpty ? text! : display
        return (name, loinc)
    }

    private static func quantityAndString(from obs: [String: Any])
        -> (Double?, String?, String?) {

        if let vq = obs["valueQuantity"] as? [String: Any] {
            var num: Double?
            if let n = vq["value"] as? NSNumber {
                num = n.doubleValue
            } else if let d = vq["value"] as? Double {
                num = d
            }
            if let num = num {
                let unit = vq["unit"] as? String ?? vq["code"] as? String
                return (num, nil, unit)
            }
        }

        if let vs = obs["valueString"] as? String {
            return (nil, vs, nil)
        }

        if let vcc = obs["valueCodeableConcept"] as? [String: Any] {
            let t = textFromCodableConcept(vcc)
            if !t.isEmpty { return (nil, t, nil) }
        }

        if let vbool = obs["valueBoolean"] as? Bool {
            return (nil, vbool ? "Positive" : "Negative", nil)
        }

        return (nil, nil, nil)
    }

    private static func textFromCodableConcept(_ cc: [String: Any]) -> String {
        if let t = cc["text"] as? String { return t }
        if let codings = cc["coding"] as? [[String: Any]] {
            return codings.compactMap { $0["display"] as? String }.joined(separator: ", ")
        }
        return ""
    }

    private static func observationDate(_ obs: [String: Any]) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let keys = ["effectiveDateTime", "effectiveInstant", "issued"]
        for k in keys {
            if let s = obs[k] as? String {
                if let d = formatter.date(from: s) ?? ISO8601DateFormatter().date(from: s) {
                    return d
                }
            }
        }

        let metaDict = obs["meta"] as? [String: Any]
        if let lm = metaDict?["lastUpdated"] as? String,
           let d = formatter.date(from: lm) ?? ISO8601DateFormatter().date(from: lm) {
            return d
        }

        return Date()
    }

    /// First referenceRange low/high + optional text (handles array or single object).
    private static func referenceRangeTriple(from rrField: Any?)
        -> (Double?, Double?, String?) {

        let rr0: [String: Any]?
        if let one = rrField as? [String: Any] {
            rr0 = one
        } else if let list = rrField as? [[String: Any]], let first = list.first {
            rr0 = first
        } else {
            return (nil, nil, nil)
        }

        guard let rr = rr0 else { return (nil, nil, nil) }

        var lowNum: Double?
        var highNum: Double?

        if let low = rr["low"] as? [String: Any] {
            if let lv = low["value"] as? NSNumber {
                lowNum = lv.doubleValue
            } else if let dv = low["value"] as? Double {
                lowNum = dv
            }
        }
        if let hi = rr["high"] as? [String: Any] {
            if let hv = hi["value"] as? NSNumber {
                highNum = hv.doubleValue
            } else if let dh = hi["value"] as? Double {
                highNum = dh
            }
        }

        let text = rr["text"] as? String
        let rangeTextFromNums: String? = {
            guard lowNum != nil || highNum != nil else { return nil }
            var parts: [String] = []
            if let l = lowNum { parts.append("\(l)") }
            if let h = highNum { parts.append("\(h)") }
            guard !parts.isEmpty else { return nil }
            if parts.count == 2 {
                return "\(parts[0]) – \(parts[1])"
            }
            return parts[0]
        }()

        if let t = text, !t.isEmpty {
            return (lowNum, highNum, t)
        }
        if let n = rangeTextFromNums {
            return (lowNum, highNum, n)
        }
        return (lowNum, highNum, nil)
    }
}
