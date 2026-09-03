# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# Spanish-language model names whose default pluralization breaks Rails helpers.
# English inflector turns "venta" into "ventum" (Latin-style) and similar quirks,
# which makes form_with model: @venta generate ventum_path. Declare irregular pairs.
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "venta", "ventas"
  # PreAlerta: sin esta regla `pre_alerta`.singularize → "pre_alertum"
  # (regla Latin -a → -um). Causa que polymorphic_path(@pre_alerta)
  # busque `pre_alertum_path` que no existe.
  inflect.irregular "pre_alerta", "pre_alertas"
  inflect.irregular "nota_debito",      "notas_debito"
  inflect.irregular "nota_credito",     "notas_credito"
  inflect.irregular "nota_debito_item", "nota_debito_items"
  inflect.irregular "nota_credito_item", "nota_credito_items"
  inflect.irregular "cotizacion", "cotizaciones"
  inflect.irregular "cotizacion_item", "cotizacion_items"
  inflect.irregular "financiamiento", "financiamientos"
  inflect.irregular "financiamiento_cuota", "financiamiento_cuotas"
  inflect.irregular "entrega", "entregas"
  inflect.irregular "apertura_caja", "aperturas_caja"
  inflect.irregular "ingreso_caja", "ingresos_caja"
  inflect.irregular "egreso_caja", "egresos_caja"
  inflect.irregular "sucursal", "sucursales"
  inflect.irregular "proveedor", "proveedores"
  inflect.irregular "tarifa_recolecta", "tarifas_recolecta"
  inflect.irregular "servicio_extra",   "servicios_extra"
  inflect.irregular "motivo_retencion", "motivos_retencion"
  inflect.irregular "paquete_motivo_retencion", "paquete_motivos_retencion"
  # C18-06: sin esto `has_many :motivos_envio_politica` no da
  # `motivo_envio_politica_ids` y las rutas del catálogo chocan.
  inflect.irregular "motivo_envio_politica", "motivos_envio_politica"
  inflect.irregular "paquete_motivo_envio_politica", "paquete_motivos_envio_politica"
  inflect.irregular "plantilla_nota_cliente", "plantillas_notas_cliente"
  # C19-04: sin esto singular y plural empatan y las rutas del catálogo de
  # descripciones salen como `plantillas_descripcion_index_path`.
  inflect.irregular "plantilla_descripcion", "plantillas_descripcion"
  # C21-11: «guia» cae en la regla Latin -a → -um igual que `pre_alerta`, así
  # que `ManifiestoGuia`.tableize daba `manifiesto_guia` (singular) y el
  # `has_many :guias` consultaba una tabla que no existe.
  inflect.irregular "manifiesto_guia", "manifiesto_guias"
  # PR-13.d: sin esto `has_many :autorizaciones` busca la clase `Autorizacione`.
  inflect.irregular "autorizacion", "autorizaciones"
end
