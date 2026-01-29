// Whisker - A SwiftUI-style framework for terminal user interfaces
//
// Re-export all public types

// Core
@_exported import struct Foundation.Data

// The actual exports happen through the module - each file in Sources/Whisker
// is automatically part of the module. This file exists to provide a central
// documentation point and any module-level code.

/// Whisker version
public let version = "0.1.0"
