// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/quotor"
import topbar from "../vendor/topbar"

// ---------- Hooks Quotor ----------
const Hooks = {}

// Carte d'extrait : clic = lecture avec le son, un seul extrait joue à la fois.
Hooks.QuoteVideo = {
  mounted() {
    this.video = this.el.querySelector("video")
    if (!this.video) return
    this.toggle = (e) => {
      if (e.target.closest("a, button:not([data-play])")) return
      e.preventDefault()
      if (this.video.paused) {
        document.querySelectorAll(".quote-card video").forEach(v => { if (v !== this.video) v.pause() })
        this.video.muted = false
        this.video.currentTime = 0
        this.video.play().catch(() => {})
      } else {
        this.video.pause()
      }
    }
    this.onPlay = () => this.el.classList.add("is-playing")
    this.onStop = () => this.el.classList.remove("is-playing")
    this.el.addEventListener("click", this.toggle)
    this.video.addEventListener("play", this.onPlay)
    this.video.addEventListener("pause", this.onStop)
    this.video.addEventListener("ended", this.onStop)
  },
  destroyed() {
    this.el.removeEventListener("click", this.toggle)
  }
}

// Bouton « copier le lien »
Hooks.CopyLink = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()
      const url = new URL(this.el.dataset.url, window.location.origin).toString()
      const label = this.el.querySelector("[data-label]")
      const done = () => {
        if (!label) return
        const old = label.textContent
        label.textContent = "Lien copié !"
        setTimeout(() => label.textContent = old, 1500)
      }
      if (navigator.clipboard) navigator.clipboard.writeText(url).then(done, done)
      else { window.prompt("Lien à copier :", url) }
    })
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#f5d000"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

