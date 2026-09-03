require "test_helper"

# Un Chrome como el de la calle: **con** el bloqueador de popups.
#
# Chromedriver arranca Chrome con `--disable-popup-blocking`, así que en los
# system tests un `window.open` sin ningún gesto del usuario abre igual y dos
# seguidas abren dos. Con ese navegador, un test sobre popups da verde aunque el
# navegador de verdad se coma la ventana — que es exactamente cómo se nos pasó
# el Warehouse Receipt que Yusef nunca vio.
#
# Va como driver **con nombre propio** y no como un bloque en `driven_by`: un
# `driven_by :selenium` por clase no alcanza, porque Capybara reusa la sesión
# —y por lo tanto el navegador— de la primera clase que haya corrido. Se
# comprobó: en `bin/rails test test/system` completo, la clase con el bloque
# heredaba el Chrome permisivo. Con un nombre distinto, el navegador es otro.
Capybara.register_driver :chrome_con_bloqueador_de_popups do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--window-size=1400,1400")
  options.exclude_switches = [ "disable-popup-blocking" ]
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  # ── Hacer observable una carrera ────────────────────────────────────────
  #
  # El servidor de test contesta más rápido de lo que Capybara teclea, así que
  # las carreras entre el teclado y una respuesta **no existen** salvo que se
  # las provoque. Estos dos helpers monkeypatchean `window.fetch` para eso.
  #
  # Salieron de `etiquetar_escaneo_rapido_test` (PR-C6.21), donde ya había uno
  # así para el tracking; C20-10 los necesitó también para el autocomplete, y
  # duplicarlos habría sido la tercera copia de la misma idea.

  # Todas las respuestas que matcheen `patron` llegan tarde. Es la latencia de
  # verdad: sirve para adelantársele al dropdown con el teclado.
  #
  # Los 800 ms están medidos, no elegidos al azar: son los que dejan meter el
  # Enter antes de que aterrice la respuesta sin estirar la suite. Subirlos
  # **empeora** — se probó con 2500 y las fallas pasaron de ~1 a 4-5 por
  # corrida, porque la demora se le come el `wait` de los asserts que vienen
  # después. Si un test de carrera falla, el problema no es este número.
  def demorar(patron, ms: 800)
    page.execute_script(<<~JS, patron, ms)
      const patron = arguments[0], ms = arguments[1]
      const original = window.fetch
      window.fetch = function (...args) {
        const promesa = original.apply(this, args)
        if (!String(args[0]).includes(patron)) return promesa
        return promesa.then((r) => new Promise((resolver) => setTimeout(() => resolver(r), ms)))
      }
    JS
  end

  # Solo la PRIMERA respuesta llega tarde, y avisa cuando la suelta. Es el
  # orden de llegada invertido: la vieja aterriza después de la nueva.
  def retener_la_primera(patron, ms: 1500)
    page.execute_script(<<~JS, patron, ms)
      const patron = arguments[0], ms = arguments[1]
      window.__respuestaTardia = false
      const original = window.fetch
      let consultas = 0
      window.fetch = function (...args) {
        const promesa = original.apply(this, args)
        if (!String(args[0]).includes(patron)) return promesa
        consultas += 1
        if (consultas !== 1) return promesa
        return promesa.then((r) => new Promise((resolver) => {
          setTimeout(() => { window.__respuestaTardia = true; resolver(r) }, ms)
        }))
      }
    JS
  end

  # ── Una sola ventana por test ───────────────────────────────────────────
  #
  # `Capybara.reset_sessions!` borra cookies y manda la ventana actual a
  # `about:blank`, pero **no cierra las ventanas que abrió el test**. El
  # `window.open` de la impresión de etiquetas nace del turbo-stream del
  # guardado —o sea, tarde— y le sobrevive al teardown: el worker sigue con dos
  # ventanas y Capybara manejando la de atrás.
  #
  # Y la de atrás no es un detalle cosmético. Chrome le pone
  # `document.visibilityState = "hidden"` a la ventana sin foco, y a una ventana
  # oculta **le congela el reloj de las animaciones**. `animate-fade-in-up`
  # arranca en `opacity: 0`, así que queda clavada ahí para siempre
  # —`getAnimations()` la muestra `running` con `currentTime: 0`— y Selenium,
  # que multiplica la opacidad de los ancestros, decide que lo de adentro no
  # está visible. El síntoma es
  #
  #     Unable to find visible field "email_address" that is not disabled
  #
  # en un test cualquiera, distinto en cada corrida, que pasa solo. Ojo con ese
  # mensaje: el "that is not disabled" es texto fijo de Capybara para cualquier
  # búsqueda de campo, no una pista de que el input esté deshabilitado — se
  # comprobó con `el.disabled === false` en el momento de la falla. Y la captura
  # engaña igual: muestra el login perfecto porque sacarla obliga a Chrome a
  # pintar un cuadro y la animación se destraba justo ahí.
  #
  # `animate-fade-in-up` no es solo del login: la usan también /passwords,
  # /pre_alertas/new, el portal del cliente y el hero del dashboard. Por eso el
  # arreglo vive acá y no dentro de `ingresar` — lo que se garantiza es una sola
  # ventana por test, no un parche por pantalla.
  #
  # Va en `setup` y no en `teardown` a propósito: la ventana de la impresión
  # puede nacer *después* de que el `ensure` del test cerró las que había, y
  # para cuando corre el setup del siguiente ya existe sí o sí.
  setup { cerrar_pestanas_extra }

  # Deja abierta solo la ventana principal y vuelve a ella.
  #
  # Cada `close` va con su rescue porque la etiqueta se cierra sola con
  # `window.close()` al terminar de imprimir: la ventana puede desaparecer entre
  # el `window_handles` y el `switch_to`.
  def cerrar_pestanas_extra
    navegador = page.driver.browser
    principal = navegador.window_handles.first
    return if principal.nil?

    navegador.window_handles.drop(1).each do |handle|
      navegador.switch_to.window(handle)
      navegador.close
    rescue Selenium::WebDriver::Error::NoSuchWindowError
      nil
    end
    navegador.switch_to.window(principal)
  rescue Selenium::WebDriver::Error::NoSuchWindowError
    nil
  end

  # La ventana de la impresión nace del turbo-stream del guardado, o sea después
  # del click. Esperarla es lo que permite cerrarla dentro del mismo test: si se
  # cierra antes de que nazca, la huérfana igual queda.
  def esperar_pestana_de_impresion(segundos: 5)
    limite = Process.clock_gettime(Process::CLOCK_MONOTONIC) + segundos
    until page.driver.browser.window_handles.size > 1
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > limite

      sleep 0.1
    end
  end

  # ── Entrar al sistema ───────────────────────────────────────────────────
  #
  # Dieciocho archivos tenían su propio `ingresar`, todos con la misma forma:
  # `visit new_session_path` y llenar el form.
  #
  # Este helper llegó a tener un fallback que borraba cookies y volvía a
  # visitar, con el cuento de que `/session/new` redirige cuando ya hay sesión
  # abierta. **No redirige nunca**: `SessionsController` la declara con
  # `allow_unauthenticated_access only: %i[new create destroy]`, y eso lo único
  # que hace es saltear el `before_action` — el form se renderiza igual, con
  # sesión y sin ella. O sea que el fallback tapaba un caso imposible, y en el
  # caso real —el campo está pero Selenium no lo ve, ver `cerrar_pestanas_extra`—
  # borrar cookies no arreglaba nada.
  def ingresar(user, password: "password123", wait: 8)
    visit new_session_path
    destrabar_animacion_de_entrada

    fill_in "email_address", with: user.email_address, wait: wait
    fill_in "password", with: password
    click_on "Iniciar Sesion"
    assert_no_current_path new_session_path, wait: wait
  end

  # El cinturón de `cerrar_pestanas_extra`: con una sola ventana la animación
  # corre sola y esto no hace falta, pero si alguna vez vuelve a haber una
  # ventana de más, acá la animación se termina a mano en vez de dejar el login
  # invisible ocho segundos.
  #
  # El orden importa. Primero se espera a que la animación **exista** —Stimulus
  # monta el controller después del `load`, y el class lo pone `connect()`—,
  # porque un `finish()` disparado antes no encuentra nada que terminar y la
  # animación se congela igual, después. `visible: :all` porque si ya está
  # congelada el contenedor está en `opacity: 0`, que es justo lo que se viene a
  # destrabar.
  #
  # El try/catch por animación no es decorativo: `finish()` tira
  # `InvalidStateError` sobre una animación infinita, y alcanzaría con que
  # alguien le ponga un `animate-pulse` a esta pantalla para tumbar todos los
  # logins de la suite.
  def destrabar_animacion_de_entrada
    page.has_css?("[data-controller='login'].animate-fade-in-up", visible: :all, wait: 5)
    page.execute_script(<<~JS)
      document.getAnimations().forEach((a) => { try { a.finish() } catch (_e) {} })
    JS
  end

  # ── Abrir /etiquetar con el tipo que se pide ────────────────────────────
  #
  # Trece archivos tenían su propio `abrir_etiquetar`, y todos con la misma
  # forma:
  #
  #     visit etiquetar_path
  #     if page.has_text?("¿Qué tipo de envío vas a trabajar?", wait: 3)
  #       first("form[...] button").click     # ← el primero, o sea CEM
  #     end
  #
  # **Ese `if` es el que fabricaba los flakes.** Si un test anterior dejó una
  # sesión abierta, el selector no aparece, el bloque no corre y el test sigue
  # con el tipo que dejó el otro. Los `first(...)` abren CEM —la lista va
  # `order(:nombre)`—, así que un archivo que necesita CER pasaba solo y fallaba
  # revuelto, con un aviso legítimo de conflicto de tipo que el test no
  # esperaba. Tres tests distintos fallaron en dos corridas seguidas de la suite
  # completa, y los tres pasaban en aislado.
  #
  # Acá la sesión vieja **se cierra** antes de elegir, así que el tipo es el que
  # se pidió y no el que sobró.
  def abrir_sesion_etiquetar(tipo)
    visit etiquetar_path
    cerrar_sesion_etiquetar_si_hay_una
    find("button[name='tipo_envio_id'][value='#{tipo.id}']").click
    assert_selector "#paquete_tracking", wait: 5
  end

  BOTON_FINALIZAR_SESION = "Finalizar sesión de este tipo de envío".freeze
  MODAL_CONFIRMAR = "[data-controller='confirm-modal']".freeze

  def cerrar_sesion_etiquetar_si_hay_una
    return if page.has_text?("¿Qué tipo de envío vas a trabajar?", wait: 3)
    return unless page.has_button?(BOTON_FINALIZAR_SESION, wait: 3)

    # El botón lleva `turbo_confirm`, y ese confirm tiene tres formas según qué
    # alcanzó a montar:
    #
    #   1. Turbo todavía no montó → el form se manda derecho, no hay diálogo.
    #   2. Turbo sí, `confirm-modal` no → `window.confirm` nativo.
    #   3. Los dos montados → `application.js` le pasa a
    #      `Turbo.setConfirmMethod` un lambda que usa `window.cecConfirm`, o sea
    #      el modal de HTML de `shared/_confirm_modal`.
    #
    # La 3 es la normal, y era la que faltaba: ahí `accept_confirm` revienta con
    # `ModalNotFound` **y el modal de HTML queda abierto**. Con el `rescue`
    # vacío de antes la sesión no se cerraba, `abrir_sesion_etiquetar` seguía
    # con el tipo de envío que sobró y el test fallaba revuelto, quejándose de
    # un texto que no estaba porque la pantalla no era la que creía.
    begin
      accept_confirm { click_on BOTON_FINALIZAR_SESION }
    rescue Capybara::ModalNotFound
      within(MODAL_CONFIRMAR) { click_on "Confirmar" } if page.has_css?(MODAL_CONFIRMAR, wait: 3)
    end
    assert_text "¿Qué tipo de envío vas a trabajar?", wait: 5
  end

  def esperar_respuesta_tardia(segundos: 5)
    limite = Process.clock_gettime(Process::CLOCK_MONOTONIC) + segundos
    until page.evaluate_script("window.__respuestaTardia === true")
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > limite

      sleep 0.1
    end
  end
end
