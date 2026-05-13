import { Application } from "@hotwired/stimulus"
import { controllerDefinitions as bulletTrainControllers } from "@bullet-train/bullet-train"
import { controllerDefinitions as bulletTrainFieldControllers } from "@bullet-train/fields"
import { controllerDefinitions as bulletTrainSortableControllers } from "@bullet-train/bullet-train-sortable"
import ScrollReveal from 'stimulus-scroll-reveal'
import RevealController from 'stimulus-reveal'
import CableReady from 'cable_ready'
import consumer from '../channels/consumer'

// Explicit imports for this app's custom Stimulus controllers.
// We used to rely on `import { context } from './**/*_controller.js'` (an
// esbuild glob plugin), but that pipeline silently emitted an empty bundle
// any time a transitive dep failed to resolve (e.g. easymde missing from
// node_modules), which kept shipping a JS-less app to production. Explicit
// registrations fail loud at build time instead.
import SegmentTranslatorController from "./segment_translator_controller"
import MarkdownEditorController from "./markdown_editor_controller"
import AiDrafterController from "./ai_drafter_controller"
import CampaignPreviewController from "./campaign_preview_controller"
import SubscriberSearchController from "./subscriber_search_controller"

const application = Application.start()

// In the browser console:
// * Type `window.Stimulus.debug = true` to log actions and lifecycle hooks
//   on subsequent user interactions and Turbo page views.
// * Type `window.Stimulus.router.modulesByIdentifier` for a list of loaded controllers.
// See https://stimulus.hotwired.dev/handbook/installing#debugging
window.Stimulus = application

application.register('reveal', RevealController)
application.register('scroll-reveal', ScrollReveal)

// Bullet Train's controllers come from the gems as an array of
// { identifier, controllerConstructor } pairs. Load them first…
let controllers = overrideByIdentifier([
  ...bulletTrainControllers,
  ...bulletTrainFieldControllers,
  ...bulletTrainSortableControllers,
])

application.load(controllers)

// …then register this app's controllers explicitly so any missing import
// surfaces as a build error rather than a silent dead button.
application.register('segment-translator', SegmentTranslatorController)
application.register('markdown-editor', MarkdownEditorController)
application.register('ai-drafter', AiDrafterController)
application.register('campaign-preview', CampaignPreviewController)
application.register('subscriber-search', SubscriberSearchController)

CableReady.initialize({ consumer })

function overrideByIdentifier(controllers) {
  const byIdentifier = {}

  controllers.forEach(item => {
    byIdentifier[item.identifier] = item
  })

  return Object.values(byIdentifier)
}
