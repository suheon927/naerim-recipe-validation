// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NaerimRecipeValidation",
    products: [
        .library(name: "RecipeValidation", targets: ["RecipeValidation"])
    ],
    targets: [
        .target(name: "RecipeValidation"),
        .testTarget(name: "RecipeValidationTests", dependencies: ["RecipeValidation"])
    ]
)
