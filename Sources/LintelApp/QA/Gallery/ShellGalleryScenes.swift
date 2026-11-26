#if DEBUG
import LintelUI

/// DEBUG only: the design gallery scenes of the shell itself (the screens `LintelApp` owns, which no plugin brings).
/// `GalleryCatalog` adds them as the group "shell". One scene per screen a PR touches (`docs/design-gallery.md`).
enum ShellGallery: GalleryProviding {
    static var galleryScenes: [GalleryScene] { OnboardingGallery.scenes }
}
#endif
