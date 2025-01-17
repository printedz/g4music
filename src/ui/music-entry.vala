namespace G4 {

    public class MusicEntry : Gtk.Box {

        private Gtk.Image _cover = new Gtk.Image ();
        private Gtk.Label _title = new Gtk.Label (null);
        private Gtk.Label _subtitle = new Gtk.Label (null);
        private Gtk.Image _playing = new Gtk.Image ();
        private BasePaintable _paintable = new BasePaintable ();
        private Music? _music = null;

        public ulong first_draw_handler = 0;

        public MusicEntry (bool compact = true) {
            var cover_margin = compact ? 5 : 6;
            var cover_size = compact ? 36 : 48;
            _cover.margin_top = cover_margin;
            _cover.margin_bottom = cover_margin;
            _cover.pixel_size = cover_size;
            _cover.paintable = new RoundPaintable (_paintable);
            _paintable.queue_draw.connect (_cover.queue_draw);
            append (_cover);

            var spacing = compact ? 2 : 6;
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, spacing);
            vbox.hexpand = true;
            vbox.valign = Gtk.Align.CENTER;
            vbox.margin_start = 12;
            vbox.margin_end = 4;
            vbox.append (_title);
            vbox.append (_subtitle);
            append (vbox);

            _title.halign = Gtk.Align.START;
            _title.ellipsize = Pango.EllipsizeMode.END;
            _title.add_css_class ("title-leading");

            _subtitle.halign = Gtk.Align.START;
            _subtitle.valign = Gtk.Align.CENTER;
            _subtitle.ellipsize = Pango.EllipsizeMode.END;
            _subtitle.add_css_class ("dim-label");
            var font_size = _subtitle.get_pango_context ().get_font_description ().get_size () / Pango.SCALE;
            if (font_size >= 13)
                _subtitle.add_css_class ("title-secondly");

            _playing.valign = Gtk.Align.CENTER;
            _playing.icon_name = "media-playback-start-symbolic";
            _playing.pixel_size = 12;
            _playing.add_css_class ("dim-label");
            append (_playing);

            //  Make enough space for text
            var height = (int) (font_size * 2.65) + spacing;
            var padding = 2;
            var item_height = (height + padding + 3) / 4 * 4;
            height_request = int.max (item_height - padding, cover_size + cover_margin * 2);

            make_right_clickable (this, show_popover);
        }

        public BasePaintable cover {
            get {
                return _paintable;
            }
        }

        public Gdk.Paintable? paintable {
            set {
                _paintable.paintable = value;
            }
        }

        public bool playing {
            set {
                _playing.visible = value;
            }
        }

        public void disconnect_first_draw () {
            if (first_draw_handler != 0) {
                _paintable.disconnect (first_draw_handler);
                first_draw_handler = 0;
            }
        }

        public void update (Music music, uint sort) {
            _music = music;
            switch (sort) {
                case SortMode.ALBUM:
                    _title.label = music.album;
                    _subtitle.label = (0 < music.track < int.MAX) ? @"$(music.track). $(music.title)" : music.title;
                    break;

                case SortMode.ARTIST:
                    _title.label = music.artist;
                    _subtitle.label = music.title;
                    break;

                case SortMode.ARTIST_ALBUM:
                    _title.label = @"$(music.artist): $(music.album)";
                    _subtitle.label = (0 < music.track < int.MAX) ? @"$(music.track). $(music.title)" : music.title;
                    break;

                case SortMode.RECENT:
                    var date = new DateTime.from_unix_local (music.modified_time);
                    _title.label = music.title;
                    _subtitle.label = date.format ("%x %H:%M");
                    break;

                default:
                    _title.label = music.title;
                    _subtitle.label = music.artist;
                    break;
            }
        }

        private void show_popover (double x, double y) {
            var app = (Application) GLib.Application.get_default ();
            app.popover_music = _music;
            if (_music != null) {
                var music = (!)_music;
                var has_cover = app.thumbnailer.find (music) is Gdk.Texture;
                var popover = create_music_popover_menu (music, x, y, music != app.current_music, has_cover);
                popover.set_parent (this);
                popover.closed.connect (() => {
                    run_idle_once (() => {
                        if (app.popover_music == music)
                            app.popover_music = null;
                    });
                });
                popover.popup ();
            }
        }
    }

    public Gtk.PopoverMenu create_music_popover_menu (Music music, double x, double y, bool play_at_next = true, bool has_cover = true) {
        var menu = new Menu ();
        if (play_at_next)
            menu.append (_("Play at Next"), ACTION_APP + ACTION_PLAY_AT_NEXT);
        menu.append (_("Search Title"), ACTION_APP + ACTION_SEARCH_TITLE);
        menu.append (_("Search Album"), ACTION_APP + ACTION_SEARCH_ALBUM);
        menu.append (_("Search Artist"), ACTION_APP + ACTION_SEARCH_ARTIST);
        menu.append (_("_Show Music File"), ACTION_APP + ACTION_SHOW_MUSIC_FILES);
        if (music.cover_uri != null)
            menu.append (_("Show _Cover File"), ACTION_APP + ACTION_SHOW_COVER_FILE);
        else if (has_cover)
            menu.append (_("_Export Cover"), ACTION_APP + ACTION_EXPORT_COVER);

        var rect = Gdk.Rectangle ();
        rect.x = (int)x;
        rect.y = (int)y;
        rect.width = rect.height = 0;

        var popover = new Gtk.PopoverMenu.from_model (menu);
        popover.autohide = true;
        popover.halign = Gtk.Align.START;
        popover.has_arrow = false;
        popover.pointing_to = rect;
        return popover;
    }

    public delegate void Pressed (double x, double y);

    public void make_right_clickable (Gtk.Widget widget, Pressed pressed) {
        var long_press = new Gtk.GestureLongPress ();
        long_press.pressed.connect ((x, y) => pressed (x, y));
        var right_click = new Gtk.GestureClick ();
        right_click.button = Gdk.BUTTON_SECONDARY;
        right_click.pressed.connect ((n, x, y) => pressed (x, y));
        widget.add_controller (long_press);
        widget.add_controller (right_click);
    }
}
