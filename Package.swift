// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CombineBluetoothService",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CombineBluetoothService",
            targets: ["CombineBluetoothService"]),
    ],
    dependencies: [
        .package(url: "git@github.com:Penjat/GenericService.git", from: "1.0.9")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CombineBluetoothService",
        dependencies: [
            "GenericService"
        ]),
        .testTarget(
            name: "CombineBluetoothServiceTests",
            dependencies: ["CombineBluetoothService"]),
    ]
)
