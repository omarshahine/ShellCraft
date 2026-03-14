# PaperKit Integration Patterns

> **Note:** PaperKit is new in iOS 26. API surface is based on WWDC25 session content and Xcode 26 beta SDK headers. Type names and method signatures may change before final release. Verify against the latest SDK.

PaperKit extends PencilKit with a complete markup experience including shapes,
text, images, stickers, and loupes. Available on iOS 26+, iPadOS 26+,
macOS 26+, and visionOS 26+.

## Contents

- [PaperMarkupViewController Setup](#papermarkupviewcontroller-setup)
- [PaperMarkup Data Model](#papermarkup-data-model)
- [Feature Sets](#feature-sets)
- [Markup Toolbar and Edit Controllers](#markup-toolbar-and-edit-controllers)
- [Integrating PencilKit Drawings](#integrating-pencilkit-drawings)
- [Shapes and Text](#shapes-and-text)
- [Data Persistence](#data-persistence)
- [SwiftUI Hosting](#swiftui-hosting)

## PaperMarkupViewController Setup

`PaperMarkupViewController` is the primary view controller for markup
experiences. It supports drawing, shapes, text, images, and more.

```swift
import PaperKit
import PencilKit

class MarkupViewController: UIViewController, PaperMarkupViewController.Delegate {
    let markupVC = PaperMarkupViewController(
        markup: nil,
        supportedFeatureSet: .latest
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        markupVC.delegate = self
        markupVC.directTouchMode = .drawing

        addChild(markupVC)
        view.addSubview(markupVC.view)
        markupVC.view.frame = view.bounds
        markupVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        markupVC.didMove(toParent: self)
    }

    func paperMarkupViewControllerDidChangeMarkup(
        _ controller: PaperMarkupViewController
    ) {
        // Markup changed -- save data
    }

    func paperMarkupViewControllerDidBeginDrawing(
        _ controller: PaperMarkupViewController
    ) {
        // User started drawing
    }

    func paperMarkupViewControllerDidChangeSelection(
        _ controller: PaperMarkupViewController
    ) {
        // Selection changed
    }
}
```

### Touch Modes

```swift
// Drawing mode: touches create strokes
markupVC.directTouchMode = .drawing

// Selection mode: touches select objects
markupVC.directTouchMode = .selection

// Configure indirect pointer (mouse/trackpad) behavior separately
markupVC.indirectPointerTouchMode = .selection
```

### Setting the Drawing Tool

PaperKit reuses PencilKit tools for drawing.

```swift
markupVC.drawingTool = PKInkingTool(.pen, color: .black, width: 3)
markupVC.drawingTool = PKEraserTool(.vector)
```

## PaperMarkup Data Model

`PaperMarkup` is the data model that stores all markup content including
drawings, shapes, text boxes, images, and stickers.

```swift
import PaperKit

// Create a new markup with a canvas size
let markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 1024, height: 768))

// Get the render frame for content
let renderFrame = markup.contentsRenderFrame

// Get searchable text content
let searchText = markup.indexableContent
```

## Feature Sets

Control which features are available in the markup experience.

```swift
// All features
let fullFeatureSet = FeatureSet.latest  // Verify case names against Xcode 26 SDK

// Minimal drawing-only feature set
var drawingOnly = FeatureSet.empty  // Verify case names against Xcode 26 SDK
drawingOnly.insert(.drawing)

// Configure available inks
var customFeatures = FeatureSet.latest
customFeatures.inks = [.pen, .pencil, .marker]

// Configure available shapes
customFeatures.shapes = [.rectangle, .ellipse, .line, .arrowShape]

// Available features:
// .drawing, .text, .images, .stickers, .loupes,
// .shapeFills, .shapeStrokes, .shapeOpacity, .links
```

### Content Version

Map PaperKit content versions to PencilKit versions.

```swift
let featureSet = FeatureSet.version1  // Verify case names against Xcode 26 SDK
let pkVersion = featureSet.contentVersion.pencilKitContentVersion
// Use with PKCanvasView.maximumSupportedContentVersion
```

## Markup Toolbar and Edit Controllers

### MarkupToolbarViewController

Provides a toolbar with drawing tools, shapes, and editing controls.

```swift
let toolbar = MarkupToolbarViewController(supportedFeatureSet: .latest)
toolbar.delegate = self

// Add as child view controller
addChild(toolbar)
view.addSubview(toolbar.view)
toolbar.didMove(toParent: self)

// Access selected tool
let currentTool = toolbar.selectedDrawingTool
let currentItem = toolbar.selectedDrawingToolItem
let touchMode = toolbar.selectedIndirectPointerTouchMode
```

### MarkupEditViewController

Provides editing actions for inserting shapes, text, and content.

```swift
let editVC = MarkupEditViewController(
    supportedFeatureSet: .latest,
    additionalActions: [
        UIAction(title: "Custom Action") { _ in
            // Handle custom action
        }
    ]
)
editVC.delegate = self
```

### Delegate Methods

```swift
extension MyController: MarkupToolbarViewController.Delegate {
    func markupToolbarViewController(
        _ controller: MarkupToolbarViewController,
        insertNewShape shape: ShapeConfiguration.Shape
    ) {
        // Insert a shape into the markup
    }

    func markupToolbarViewControllerInsertNewTextbox(
        _ controller: MarkupToolbarViewController
    ) {
        // Insert a text box
    }

    func markupToolbarViewControllerSelectedDrawingToolChanged(
        _ controller: MarkupToolbarViewController
    ) {
        markupVC.drawingTool = controller.selectedDrawingTool
    }
}
```

## Integrating PencilKit Drawings

Append PencilKit drawings directly into PaperMarkup data.

```swift
import PaperKit
import PencilKit

// Append a PKDrawing to PaperMarkup
let pkDrawing = canvasView.drawing
var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 1024, height: 768))
markup.append(contentsOf: pkDrawing)

// Combine PaperMarkup documents
let otherMarkup = PaperMarkup(bounds: .zero)
markup.append(contentsOf: otherMarkup)
```

## Shapes and Text

### Inserting Shapes

```swift
let shapeConfig = ShapeConfiguration(
    type: .rectangle,
    fillColor: UIColor.blue.cgColor,
    strokeColor: UIColor.black.cgColor,
    lineWidth: 2
)

markup.insertNewShape(
    configuration: shapeConfig,
    frame: CGRect(x: 100, y: 100, width: 200, height: 150),
    rotation: 0
)
```

### Available Shape Types

| Shape | Description |
|---|---|
| `.rectangle` | Standard rectangle |
| `.roundedRectangle` | Rectangle with rounded corners |
| `.ellipse` | Circle or oval |
| `.line` | Straight line |
| `.arrowShape` | Line with arrowhead |
| `.star` | Star shape |
| `.regularPolygon` | Regular polygon |
| `.chatBubble` | Speech bubble |

### Inserting Lines with Markers

```swift
markup.insertNewLine(
    configuration: ShapeConfiguration(
        type: .line,
        fillColor: nil,
        strokeColor: UIColor.red.cgColor,
        lineWidth: 3
    ),
    from: CGPoint(x: 50, y: 50),
    to: CGPoint(x: 300, y: 200),
    startMarker: false,
    endMarker: true  // Arrowhead at end
)
```

### Inserting Text Boxes

```swift
let attributedText = AttributedString("Hello, PaperKit!")

markup.insertNewTextbox(
    attributedText: attributedText,
    frame: CGRect(x: 100, y: 400, width: 300, height: 50),
    rotation: 0
)
```

### Inserting Images

```swift
let image: CGImage = // your image
markup.insertNewImage(
    image,
    frame: CGRect(x: 50, y: 50, width: 200, height: 200),
    rotation: 0
)
```

## Data Persistence

Serialize `PaperMarkup` to `Data` for storage.

```swift
// Save
func saveMarkup(_ markup: PaperMarkup, to url: URL) async throws {
    let data = try await markup.dataRepresentation()
    try data.write(to: url)
}

// Load
func loadMarkup(from url: URL) throws -> PaperMarkup {
    let data = try Data(contentsOf: url)
    return try PaperMarkup(dataRepresentation: data)
}
```

### Rendering Markup to an Image

```swift
func renderMarkup(_ markup: PaperMarkup, in rect: CGRect) async -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: rect.size)
    return await renderer.image { context in
        let cgContext = context.cgContext
        let options = RenderingOptions(traitCollection: .current)
        await markup.draw(in: cgContext, frame: rect, options: options)
    }
}
```

### Downgrading Feature Sets

Remove unsupported content when sharing with older versions.

```swift
markup.removeContentUnsupported(by: .version1)
```

## SwiftUI Hosting

Wrap `PaperMarkupViewController` in SwiftUI.

```swift
import SwiftUI
import PaperKit

struct MarkupCanvasView: UIViewControllerRepresentable {
    @Binding var markup: PaperMarkup?

    func makeUIViewController(context: Context) -> PaperMarkupViewController {
        let vc = PaperMarkupViewController(
            markup: markup,
            supportedFeatureSet: .latest
        )
        vc.delegate = context.coordinator
        vc.directTouchMode = .drawing
        return vc
    }

    func updateUIViewController(
        _ vc: PaperMarkupViewController,
        context: Context
    ) {
        // Update if needed
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PaperMarkupViewController.Delegate {
        let parent: MarkupCanvasView

        init(_ parent: MarkupCanvasView) {
            self.parent = parent
        }

        func paperMarkupViewControllerDidChangeMarkup(
            _ controller: PaperMarkupViewController
        ) {
            parent.markup = controller.markup
        }
    }
}
```
