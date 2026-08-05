#!/usr/bin/env swift

import Foundation
import SceneKit

struct RigManifest: Decodable {
    let schemaVersion: Int
    let model: String
    let rootNode: String
    let bones: [String: String]
}

enum ValidationError: Error, CustomStringConvertible {
    case usage
    case message(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: ValidateDouhuaRig.swift MANIFEST_JSON MODEL_USDZ"
        case let .message(value):
            return value
        }
    }
}

func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 2 else { throw ValidationError.usage }
    let manifestURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
    let modelURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let manifest = try JSONDecoder().decode(
        RigManifest.self,
        from: Data(contentsOf: manifestURL)
    )
    guard manifest.schemaVersion == 1 else {
        throw ValidationError.message("Unsupported manifest schema")
    }
    let scene = try SCNScene(url: modelURL, options: nil)
    guard let root = scene.rootNode.childNode(withName: manifest.rootNode, recursively: true) else {
        throw ValidationError.message("Missing root node: \(manifest.rootNode)")
    }

    let missingBones = manifest.bones
        .filter { root.childNode(withName: $0.value, recursively: true) == nil }
        .map(\.key)
        .sorted()
    guard missingBones.isEmpty else {
        throw ValidationError.message("Missing semantic bones: \(missingBones.joined(separator: ", "))")
    }

    var geometryCount = 0
    var skinnerCount = 0
    var materialCount = 0
    root.enumerateChildNodes { node, _ in
        if let geometry = node.geometry {
            geometryCount += 1
            materialCount += geometry.materials.count
        }
        if node.skinner != nil { skinnerCount += 1 }
    }
    guard geometryCount > 0 else { throw ValidationError.message("Model contains no geometry") }
    guard skinnerCount > 0 else { throw ValidationError.message("Model contains no SCNSkinner") }
    guard materialCount > 0 else { throw ValidationError.message("Model contains no material") }
    guard root.boundingBox.min.x.isFinite,
          root.boundingBox.min.y.isFinite,
          root.boundingBox.min.z.isFinite,
          root.boundingBox.max.x.isFinite,
          root.boundingBox.max.y.isFinite,
          root.boundingBox.max.z.isFinite
    else { throw ValidationError.message("Model bounding box is invalid") }

    print("PASS: root \(manifest.rootNode)")
    print("PASS: \(manifest.bones.count) semantic bones")
    print("PASS: \(geometryCount) geometries / \(skinnerCount) skinners / \(materialCount) materials")
    print("PASS: bounding box \(root.boundingBox)")
}

do {
    try main()
} catch {
    fputs("ValidateDouhuaRig failed: \(error)\n", stderr)
    exit(1)
}
