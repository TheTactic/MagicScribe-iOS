import Foundation

/// Faithful port of assets/js/builder.js's `addField()` defaults + field-id
/// counter reconstruction + `applySingleColLayout()` (lines ~45-54, 563-600,
/// 2241-2259). iOS never renders a pixel canvas — fields reflow into a
/// native vertical list instead — but every field still needs real
/// position/dimensions written on save, since builder.js's renderField()
/// crashes with no null-check if either is missing.
nonisolated enum FormLayoutEngine {
    private struct TypeDefaults {
        let w: Double
        let h: Double
        let placeholder: String
    }

    private static let typeDefaults: [String: TypeDefaults] = [
        "text":      TypeDefaults(w: 220, h: 40,  placeholder: "Enter text..."),
        "textarea":  TypeDefaults(w: 300, h: 90,  placeholder: "Enter text..."),
        "checkbox":  TypeDefaults(w: 160, h: 28,  placeholder: ""),
        "dropdown":  TypeDefaults(w: 200, h: 40,  placeholder: "Select an option"),
        "date":      TypeDefaults(w: 180, h: 40,  placeholder: "mm/dd/yyyy"),
        "signature": TypeDefaults(w: 280, h: 80,  placeholder: ""),
        "textblock": TypeDefaults(w: 300, h: 40,  placeholder: "Label or heading text"),
        "image":     TypeDefaults(w: 300, h: 200, placeholder: ""),
    ]
    private static let fallbackDefaults = TypeDefaults(w: 200, h: 40, placeholder: "")

    /// Scans every "field_NNN" id in the (flattened, cross-page) field list
    /// and returns max+1 — same reconstruction builder.js does on load. The
    /// counter must never be invented fresh when appending to an
    /// already-saved form.
    static func nextFieldCounter(in fields: [MSFField]) -> Int {
        var maxCounter = 0
        for field in fields {
            guard field.id.hasPrefix("field_"),
                  let suffix = Int(field.id.dropFirst("field_".count)) else { continue }
            maxCounter = max(maxCounter, suffix)
        }
        return maxCounter + 1
    }

    /// Ports builder.js's addField() defaults exactly, including which keys
    /// are conditionally present per type. `position`/`dimensions` get a
    /// placeholder value here — `layoutSingleColumn` always runs again right
    /// before save with the real values.
    static func makeField(type: String, label: String, counter: Int) -> MSFField {
        let defaults = typeDefaults[type] ?? fallbackDefaults
        let idSuffix = String(format: "%03d", counter)
        var field = MSFField(
            id: "field_\(idSuffix)",
            type: type,
            label: label,
            machineName: "\(type)_\(counter)",
            aiContext: "",
            placeholder: defaults.placeholder,
            required: false,
            position: MSFFieldPosition(x: 20, y: 0),
            dimensions: MSFFieldDimensions(w: defaults.w, h: defaults.h),
            style: .default
        )
        switch type {
        case "date":
            field.dateFormat = "MM/DD/YYYY"
        case "dropdown":
            field.options = []
        case "textblock":
            field.isSectionHeader = false
        case "image":
            field.src = ""
            field.objectFit = "contain"
            field.allowUserUpload = false
        default:
            break
        }
        // Every type except textblock gets this fixed-shape default —
        // textblock never gets the key at all, not even a null placeholder.
        if type != "textblock" {
            field.contextChain = MSFContextChain(sectionId: nil, groupId: nil, role: "")
        }
        return field
    }

    private static let pageLimit: Double = 1050 // CANVAS_H(1100) - 50 bottom margin

    /// Verbatim port of applySingleColLayout — run on the full flattened
    /// field list immediately before every save, regardless of the form's
    /// original page structure. Accepted v1 tradeoff: an existing multi-page
    /// web-built form's custom page labels are replaced by generic "Page N"
    /// labels the first time it's edited-and-saved on iOS.
    static func layoutSingleColumn(fields: [MSFField], startY: Double = 30) -> [[MSFField]] {
        var buckets: [[MSFField]] = [[]]
        var y = startY
        for original in fields {
            var field = original
            if y + field.dimensions.h > pageLimit && !buckets[buckets.count - 1].isEmpty {
                buckets.append([])
                y = 30
            }
            field.position = MSFFieldPosition(x: 20, y: y)
            field.dimensions.w = 760
            y += field.dimensions.h + 28
            buckets[buckets.count - 1].append(field)
        }
        return buckets
    }
}
