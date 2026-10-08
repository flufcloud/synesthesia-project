import Foundation

public struct ColorValue: Codable {
    public let hex: String
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: String, red: Double, green: Double, blue: Double) {
        self.hex = hex
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct ColorSample: Codable {
    public let timeSeconds: Double
    public let primary: ColorValue?
    public let secondary: ColorValue?
    public let tertiary: ColorValue?

    private enum CodingKeys: String, CodingKey {
        case timeSeconds
        case primary
        case secondary
        case tertiary
    }

    public init(
        timeSeconds: Double,
        primary: ColorValue?,
        secondary: ColorValue?,
        tertiary: ColorValue?
    ) {
        self.timeSeconds = timeSeconds
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeSeconds, forKey: .timeSeconds)

        if let primary {
            try container.encode(primary, forKey: .primary)
        } else {
            try container.encodeNil(forKey: .primary)
        }

        if let secondary {
            try container.encode(secondary, forKey: .secondary)
        } else {
            try container.encodeNil(forKey: .secondary)
        }

        if let tertiary {
            try container.encode(tertiary, forKey: .tertiary)
        } else {
            try container.encodeNil(forKey: .tertiary)
        }
    }
}

public struct AudioReference: Codable {
    public let fileName: String
    public let path: String
    public let durationSeconds: Double

    public init(fileName: String, path: String, durationSeconds: Double) {
        self.fileName = fileName
        self.path = path
        self.durationSeconds = durationSeconds
    }
}

public struct SamplingDescription: Codable {
    public let rateHz: Double
    public let colorSpace: String

    public init(rateHz: Double, colorSpace: String) {
        self.rateHz = rateHz
        self.colorSpace = colorSpace
    }
}

public struct Dataset: Codable {
    public let formatVersion: Int
    public let createdAt: Date
    public let audio: AudioReference
    public let sampling: SamplingDescription
    public let samples: [ColorSample]

    public init(
        formatVersion: Int,
        createdAt: Date,
        audio: AudioReference,
        sampling: SamplingDescription,
        samples: [ColorSample]
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.audio = audio
        self.sampling = sampling
        self.samples = samples
    }
}
