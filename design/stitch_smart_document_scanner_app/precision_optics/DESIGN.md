---
name: Precision Optics
colors:
  surface: '#faf8ff'
  surface-dim: '#d2d9f4'
  surface-bright: '#faf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3ff'
  surface-container: '#eaedff'
  surface-container-high: '#e2e7ff'
  surface-container-highest: '#dae2fd'
  on-surface: '#131b2e'
  on-surface-variant: '#3e4942'
  inverse-surface: '#283044'
  inverse-on-surface: '#eef0ff'
  outline: '#6e7a72'
  outline-variant: '#bdcac0'
  surface-tint: '#006c4a'
  primary: '#006948'
  on-primary: '#ffffff'
  primary-container: '#00855c'
  on-primary-container: '#f5fff7'
  inverse-primary: '#6ddbaa'
  secondary: '#006a63'
  on-secondary: '#ffffff'
  secondary-container: '#99efe5'
  on-secondary-container: '#006f67'
  tertiary: '#006194'
  on-tertiary: '#ffffff'
  tertiary-container: '#007bb9'
  on-tertiary-container: '#fdfcff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#8af8c5'
  primary-fixed-dim: '#6ddbaa'
  on-primary-fixed: '#002114'
  on-primary-fixed-variant: '#005237'
  secondary-fixed: '#9cf2e8'
  secondary-fixed-dim: '#80d5cb'
  on-secondary-fixed: '#00201d'
  on-secondary-fixed-variant: '#00504a'
  tertiary-fixed: '#cce5ff'
  tertiary-fixed-dim: '#93ccff'
  on-tertiary-fixed: '#001d31'
  on-tertiary-fixed-variant: '#004b73'
  background: '#faf8ff'
  on-background: '#131b2e'
  surface-variant: '#dae2fd'
typography:
  display-lg:
    fontFamily: Space Grotesk
    fontSize: 40px
    fontWeight: '600'
    lineHeight: 48px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 26px
    fontWeight: '600'
    lineHeight: 34px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Space Grotesk
    fontSize: 20px
    fontWeight: '500'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 18px
  label-lg:
    fontFamily: Space Grotesk
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-md:
    fontFamily: Space Grotesk
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Space Grotesk
    fontSize: 10px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.04em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-tablet: 1.5rem
  margin-desktop: 2.5rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system is tailored for an offline-first document digitization tool that prioritizes user sovereignty, optical precision, and absolute data privacy. The brand identity fuses the tactile clarity of traditional document archival with the crisp ergonomics of modern desktop-grade utility software.

### Personality & Tone
- **Utilitarian Confidence:** Clean, uncompromising utility built for speed and clarity. No superfluous ornamental fluff.
- **Privacy-First Calm:** The interface communicates local-only processing through grounded, serene emerald hues and clear state anchors.
- **Optical Crispness:** High legibility, paper-inspired canvas areas, and fine-line borders reflect the precision of physical page flattening and edge detection.

### Aesthetic Direction: Modern Precision Minimalist
Drawing from modern technical minimalism, the UI avoids heavy skeletal skeuomorphism while retaining the reassuring physicality of documents. Surfaces rely on pure white capture canvases floating over cool slate/zinc working environments. The interface leverages deliberate whitespace, razor-thin low-contrast outlines, and architectural typographic hierarchy to communicate technical authority and security.

## Colors

The palette emphasizes pure optical contrast, environmental cleanliness, and trust-centric validation markers. 

### Role Mapping & Semantic Usage
- **Primary (`#0a8f64` - Deep Forest Emerald):** Designates successful edge capture, scan confirmation, offline-safe badges, primary actions, and storage assurance.
- **Secondary (`#0f766e` - Deep Spruce Teal):** Applied to active navigation tabs, interactive tools (crop handles, perspective corner anchors), and secondary focal elements.
- **Tertiary (`#0284c7` - Technical Cyan/Blue):** Reserved for technical diagnostics, OCR processing markers, export formats (PDF, TIFF, TXT), and batch metadata indicators.
- **Neutral Foreground (`#0f172a` - Ink Slate):** High-contrast readable ink for primary headings, filenames, and extracted text. Subdued text shifts to `#334155` (Slate 700) and `#64748b` (Slate 500) for tertiary metadata.
- **Base Canvas & Surfaces:** 
  - Working Backdrop / App Frame: `#f8fafc` (Slate 50) transitioning to `#f1f5f9` (Slate 100) for control wells and side rails.
  - Document & Card Surfaces: Pure `#ffffff` (White), delivering optical separation for scanned pages.
- **Structural Dividers:** Subtle perimeter keylines utilize `#e2e8f0` (Slate 200) to keep controls tactile without competing with document content.

### Status & Privacy Signaling
- **Device-Only Badge (Privacy Green):** Background `#ecfdf5`, border `#a7f3d0`, text `#065f46`, icon `#0a8f64`. Signifies that optical inference and storage never leave local memory.

## Typography

The type system blends the geometric, engineering-grade character of **Space Grotesk** with the neutral, hyper-legible utility of **Inter**.

### Hierarchy & Application
- **Space Grotesk (Display, Headings, Technical Labels):** Delivers a technical, precision-tool aesthetic. Used for screen titles, document names, processing states, page count badges, and hardware stats (e.g., DPI, file byte sizes, scan resolution).
- **Inter (Body, Metadata, Extracted OCR):** Delivers effortless scanning across multi-line paragraphs, captured text previews, settings configurations, and privacy disclosures.
- **Tabular Figures:** All numeric readouts (page indices, MB counts, aspect ratios) must enforce `font-feature-settings: "tnum" 1` to prevent layout jitter during live scanning and processing loops.

## Layout & Spacing

The layout is constructed on an 8-point spatial rhythm with strict geometric bounds, optimizing for one-handed capture ergonomics on mobile while expanding into dual-pane workstation layouts on tablet and desktop.

### Layout Mechanics
- **Mobile Viewport (< 640px):** 4-column fluid layout with `margin: 1rem`. Bottom-anchored capture triggers, thumb-reachable toolbar strips, and full-bleed document viewfinders with floating overlays.
- **Tablet Viewport (640px – 1024px):** 8-column layout with `margin-tablet: 1.5rem`. Split canvas showcasing the active scanned thumbnail strip adjacent to the primary document editor.
- **Desktop / Workstation Viewport (> 1024px):** 12-column layout with `margin-desktop: 2.5rem` and max container bounds of 1440px. Three-pane architecture: left folder/batch tree, center high-resolution preview canvas, right inspector/OCR drawer.

## Elevation & Depth

Visual hierarchy uses a crisp "floating paper" technique that combines razor-sharp ghost borders (`#e2e8f0`) with diffused, low-opacity ambient shadows. This keeps the workspace flat and clean, allowing scanned high-contrast paper documents to emerge as the primary layer.

### Surface Tiers
- **Tier 0 (Backdrop / Canvas):** `#f8fafc`. Receded background plane for desktop work areas and mobile camera rails.
- **Tier 1 (Panels & Trays):** `#ffffff` with a crisp border (`1px solid #e2e8f0`). No drop shadow. Used for document sidebars, inspection trays, and metadata lists.
- **Tier 2 (Floating Sheets & Cards):** `#ffffff` with a double-ring boundary: `1px solid #e2e8f0` and an ambient shadow `0 2px 8px -2px rgba(15, 23, 42, 0.06), 0 1px 3px -1px rgba(15, 23, 42, 0.04)`. Represents scanned document cards and file batches.
- **Tier 3 (Viewfinder Modals & Floating Toolbars):** `#ffffff` with `0 12px 24px -6px rgba(15, 23, 42, 0.08), 0 4px 8px -3px rgba(15, 23, 42, 0.04)`. Anchors capture overlays, bottom sheets, and zoom flyouts.

## Shapes

The shape architecture relies on a **Soft (Level 1)** geometric standard. This keeps corners disciplined, clinical, and architectural—avoiding excessive consumer roundness in favor of a reliable instrument feel.

### Corner Rules
- **Base Geometry (`0.25rem` / `4px`):** Checkboxes, status pills, discrete metadata chips, inner tool controls, and context menus.
- **Intermediate Surfaces (`rounded-lg: 0.5rem` / `8px`):** Document cards, input fields, capture mode selectors, batch grouping containers, and dialog modals.
- **Structural Shells (`rounded-xl: 0.75rem` / `12px`):** Camera viewport overlays, bottom capture sheets, and global app panes.
- **Functional Exceptions (Pill `9999px`):** Camera shutter triggers, quick-action floaters, and specific edge detection crop handles to optimize fingertip contact.

## Components

### Buttons
- **Primary Action (Scan / Export):** Solid `#0a8f64` fill, white `#ffffff` text, font `label-lg`, `border-radius: 6px`. Active press state shifts to `#087350`.
- **Secondary (Edit, Filter, Re-order):** `#ffffff` fill, `#0f172a` text, perimeter border `1px solid #e2e8f0`. Hover brings surface tint `#f8fafc`.
- **Ghost Utility (Rotate, Trash, Undo):** Transparent fill, `#334155` icon and text. Hover activates `#f1f5f9`.

### Offline Indicator & Privacy Badges
- **Device-Only Anchor:** An unyielding visual anchor featured prominently in top bars and capture headers.
  - Container: Pill-shaped, background `#ecfdf5`, border `1px solid #a7f3d0`, padding `2px 8px`.
  - Icon: A shielded hard-drive or localized lock icon in `#0a8f64`.
  - Text: `label-sm` reading `ON-DEVICE ENGINE` or `OFFLINE SAFE` in `#065f46`.

### Document Cards & Thumbnail Strips
- Constructed from pure `#ffffff` bases surrounded by `1px solid #e2e8f0`.
- Scanned document thumbnail sits inside an inset preview well with a `#f1f5f9` mat and `0.25rem` radius.
- Metadata strip beneath the preview lists page numbers, auto-crop tag, and byte size using `Space Grotesk` tabular figures.

### Input Fields & Search Bars
- Background `#ffffff`, border `1px solid #cbd5e1`, placeholder `#94a3b8`, text `#0f172a`.
- Focus state switches border to `#0a8f64` with a crisp `0 0 0 2px rgba(10, 143, 100, 0.15)` optical ring.

### Chips & Filters
- **Document Tags (Receipt, Contract, ID, Note):** Background `#f1f5f9`, border `1px solid transparent`, text `#334155`.
- **Selected Filter:** Background `#ecfdf5`, border `1px solid #0a8f64`, text `#065f46`, font `label-md`.

### Selection Controls (Checkboxes & Radios)
- Crisp `16px` squares (`4px` radius) with `1px solid #cbd5e1`.
- Checked state fills with `#0a8f64`, presenting a bold `#ffffff` hairline checkmark.

### Viewfinder HUD & Edge Detection Box
- Camera preview HUD features live perspective adjustment vectors in `#0a8f64` with circular tactile handles (`16px`, white fill, `2px solid #0a8f64`).
- Guidance callouts ("Hold steady", "Edge detected") display on a high-contrast pill backdrop (`rgba(15, 23, 42, 0.85)` with `#ffffff` text).