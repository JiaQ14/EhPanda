# Gallery list architecture

Both gallery display modes now use `GalleryListView` and `GalleryListController`.
This replaces the previous SwiftUI detail `List` and the waterfall coordinator's
estimated heights, asynchronous measurement queue, and delayed offset restores.

## Viewport and search

- `gallerySearch` owns a fixed-height search area inside the page. It uses a
  normal text field, system keyboard, explicit per-page submit callback, and a
  close control. It does not rely on the old `.searchable`-only submit trigger.
- There is no `UISearchController` for these pages, so starting or cancelling
  search does not hide, restore, or resize the navigation bar.
- SwiftUI defines the available viewport, including navigation, tabs, keyboard,
  and sheet safe areas. The native scroll view uses `.never` for automatic inset
  adjustment and does not extend through the top or bottom safe areas.
- Normal navigation title behavior remains separate from search focus. Search
  intentionally does not collapse an expanded title or scroll to the search box.
- Keyboard and height-only window changes do not recompute card geometry.

## Layout and rendering

- `GalleryCardLayout` computes text, tag, image, metadata, and cache-status
  rectangles using the actual fonts and the effective content width.
- `GalleryListCard` renders those rectangles. Image loading cannot change their
  dimensions; there is no self-sizing feedback loop.
- Detail mode uses `UITableView` with explicit row heights and disabled height
  estimates. This retains native leading and trailing swipe actions.
- Waterfall mode uses `UICollectionView` with deterministic masonry rectangles.
  Appending galleries preserves existing rectangles. A spatial index limits
  visible-rectangle queries without measuring off-screen SwiftUI views.
- Both modes reuse the existing context menu, favorite submenu, download
  commands, sharing sheet, preview, and iPad drag-to-window implementation.
- Dynamic Type changes recompute fonts and card sizes. Accessibility text sizes
  reduce the waterfall column count. Right-to-left layout mirrors both columns
  and card content.

## Data lifecycle

- Duplicate gallery IDs are removed before they reach the native data source.
- Data and geometry are committed together. Real content/width/style changes
  preserve a visible gallery ID; style changes preserve its fractional position.
- A different dataset identity resets position explicitly. Keyboard focus is
  not a dataset change.
- Progress-only and other size-neutral changes reconfigure visible content
  without replacing cells or invalidating the layout.
- Updates received while dragging/decelerating are coalesced until scrolling
  ends. Native refresh control owns negative offsets and settling animations.
- Pagination is keyed by page and gallery range, preventing duplicate requests.
  Failed pagination waits for an explicit retry. Refresh tasks and image
  prefetching are cancelled when their controller is dismantled.

## Verification

`GalleryListLayoutTests` exercises geometry, append stability, spatial queries,
Dynamic Type, status sizing, and repeated search focus/cancellation through real
Home/Toplists, Home/Show All, and Popular navigation. It measures rendered cell
positions during transitions and verifies that the keyboard really appears.

`GalleryListLifecycleTests` covers append/removal, width and height changes,
style switches, dataset reset, progress updates, selection, native detail swipe
actions, refresh, pagination, search submission/cancellation, and installed
context-menu/drag interactions. Fixtures use local numbered cover images, with
no network or account-side changes.

Run these suites on both iOS 26.5 and 27, on iPhone and iPad simulators. Run the
complete `EhPandaTests` suite before publishing. Live favorite/download/share
operations still warrant device regression testing with the user's own account;
the automated tests do not perform those remote operations.
