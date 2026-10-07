# DagaWASD — Strumento di SketchUp attivo in modalità FPS: mirino e barra di carica.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # FPS Tool — blocca orbita/pan, disegna mirino
    # ══════════════════════════════════════════════════════════════
    # Qui si disegnano solo mirino e barra (2D): niente getExtents, che
    # sposterebbe Zoom estensioni; quello delle particelle sta in precip.rb.
    class FPSTool # rubocop:disable SketchupSuggestions/ToolDrawingBounds
      def activate;       Sketchup.active_model.active_view.invalidate; end
      # Sospeso da uno strumento di vista (orbita, panoramica): ridisegna,
      # così mirino e barra di carica non restano sullo schermo
      def suspend(view);   view.invalidate; end
      # Un altro strumento ha preso il posto di questo (clic sulla barra con
      # la freccia visibile, modello chiuso…): FPS non deve restare a guidare
      # la camera da solo. stop() mette @active a false prima di cambiare
      # strumento, quindi qui non si rientra.
      def deactivate(view)
        view.invalidate
        fps = DagaWASD::FPSWalk
        UI.start_timer(0) { fps.stop } if fps.instance_variable_get(:@active)
      end
      def onMouseMove(*);   true; end
      def onLButtonDown(*); true; end
      def onLButtonUp(*);   true; end
      def onRButtonDown(*); true; end
      def onRButtonUp(*);   true; end
      def onMButtonDown(*); DagaWASD::FPSWalk.reset_zoom; true; end
      def onMButtonUp(*);   true; end
      def onSetCursor; end

      # Rotella = zoom sul FOV. Ritornando true SketchUp non esegue il suo
      # zoom (che sposterebbe l'occhio, subito sovrascritto dal tick).
      # Chiamato da SketchUp 2019.2 in poi.
      def onMouseWheel(_flags, delta, _x, _y, _view)
        DagaWASD::FPSWalk.on_wheel(delta)
        true
      end

      def draw(view)
        fps = DagaWASD::FPSWalk
        return unless fps.instance_variable_get(:@active)
        unless SKY_OVERLAY                       # SketchUp prima del 2023: niente Overlay
          fps.sky_draw(view)                    # col cielo acceso disegna anche le nuvole
          fps.cloud_draw(view) unless fps.cf('sky_enabled')
          fps.snow_draw(view)
          fps.precip_draw(view)
        end
        cx = view.vpwidth / 2; cy = view.vpheight / 2
        draw_crosshair(view, fps, cx, cy) if fps.cf('crosshair')
        draw_charge_bar(view, fps, cx, cy, *fps.charge_info) if fps.charge_info
      rescue => fps_err; DagaWASD::FPSWalk.log_error(:draw, fps_err); nil; end

      # Mirino secondo Sistema › Aspetto: forma, colore, misure. Il bordo
      # scuro è la stessa figura disegnata prima, più spessa e in nero.
      def draw_crosshair(view, fps, cx, cy)
        style = fps.cf('hud_cross_style').to_s
        sz    = fps.cf('hud_cross_size').to_f.clamp(3.0, 30.0)
        g     = fps.cf('hud_cross_gap').to_f.clamp(0.0, [sz - 1.0, 12.0].min)
        lw    = fps.cf('hud_cross_width').to_i.clamp(1, 4)
        op    = fps.cf('hud_cross_opacity').to_f.clamp(0.1, 1.0)
        pt    = ->(x, y) { Geom::Point3d.new(x, y, 0) }
        arms  = [pt[cx - sz, cy], pt[cx - g, cy], pt[cx + g, cy], pt[cx + sz, cy],
                 pt[cx, cy - sz], pt[cx, cy - g], pt[cx, cy + g], pt[cx, cy + sz]]
        ring  = ->(r) { (0...24).map { |i| a = i * Math::PI / 12; pt[cx + r * Math.cos(a), cy + r * Math.sin(a)] } }
        dot_r = style == 'dot' ? [sz / 3.0, 1.5].max : lw + 0.5
        paint = lambda do |color, extra|
          view.drawing_color = color
          view.line_width    = lw + extra
          view.draw2d(GL_LINES, arms) if style == 'cross' || style == 'crossdot'
          view.draw2d(GL_LINE_LOOP, ring[sz]) if style == 'circle'
          view.draw2d(GL_POLYGON, ring[dot_r + extra / 2.0]) if style == 'dot' || style == 'crossdot'
        end
        paint.call([0, 0, 0, (op * 150).round], 2) if fps.cf('hud_cross_outline')
        paint.call(fps.rgba('hud_cross_color', op), 0)
      end

      # Barra di carica sotto il mirino. Per il lancio il tratto finale
      # (zona di topspin) è marcato e la barra cambia colore quando ci entra.
      def draw_charge_bar(view, fps, cx, cy, ratio, zone)
        w  = fps.cf('hud_bar_width').to_f.clamp(60.0, 300.0)
        h  = fps.cf('hud_bar_height').to_f.clamp(2.0, 16.0)
        x0 = cx - w / 2; y0 = cy + [26.0, fps.cf('hud_cross_size').to_f + 14.0].max
        zc = fps.rgba('hud_bar_zone_color', 0.92)
        quad = lambda do |xa, xb|
          [Geom::Point3d.new(xa, y0, 0), Geom::Point3d.new(xb, y0, 0),
           Geom::Point3d.new(xb, y0 + h, 0), Geom::Point3d.new(xa, y0 + h, 0)]
        end
        view.drawing_color = [0, 0, 0, 110]
        view.draw2d(GL_QUADS, quad.call(x0 - 1, x0 + w + 1))
        in_zone = zone && ratio >= zone
        view.drawing_color = in_zone ? zc : fps.rgba('hud_bar_color', 0.86)
        view.draw2d(GL_QUADS, quad.call(x0, x0 + w * ratio)) if ratio > 0.005
        if zone
          zx = x0 + w * zone
          view.line_width = 1
          view.drawing_color = zc
          view.draw2d(GL_LINES, [Geom::Point3d.new(zx, y0 - 3, 0), Geom::Point3d.new(zx, y0 + h + 3, 0)])
        end
      end

      def getInstructorContentDirectory; nil; end
    end

  end
end
