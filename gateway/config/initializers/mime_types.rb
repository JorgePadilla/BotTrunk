# Be sure to restart your server when you modify this file.

Mime::Type.register "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx unless Mime::Type.lookup_by_extension(:xlsx)
Mime::Type.register "application/pdf", :pdf unless Mime::Type.lookup_by_extension(:pdf)
