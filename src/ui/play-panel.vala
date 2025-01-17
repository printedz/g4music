namespace G4 {

    [GtkTemplate (ui = "/com/github/neithern/g4music/gtk/play-panel.ui")]
    public class PlayPanel : Gtk.Box {
        [GtkChild]
        private unowned Gtk.Button back_btn;
        [GtkChild]
        public unowned Gtk.Box music_box;
        [GtkChild]
        public unowned Gtk.Image music_cover;
        [GtkChild]
        private unowned Gtk.Label music_album;
        [GtkChild]
        private unowned Gtk.Label music_artist;
        [GtkChild]
        private unowned Gtk.Label music_title;
        [GtkChild]
        private unowned Gtk.Label initial_label;

        private PlayBar _play_bar = new PlayBar ();

        private Application _app;
        private int _cover_size = 1024;
        private double _degrees_per_second = 360 / 20; // 20s per lap
        private CrossFadePaintable _crossfade_paintable = new CrossFadePaintable ();
        private MatrixPaintable _matrix_paintable = new MatrixPaintable ();
        private RoundPaintable _round_paintable = new RoundPaintable ();
        private bool _rotate_cover = true;
        private bool _show_peak = true;

        public signal void cover_changed (Music? music, CrossFadePaintable cover);

        public PlayPanel (Application app, Window win, Adw.Leaflet leaflet) {
            _app = app;

            append (_play_bar);
            _play_bar.position_seeked.connect (on_position_seeked);

            leaflet.bind_property ("folded", back_btn, "visible", BindingFlags.SYNC_CREATE);
            back_btn.clicked.connect (() => leaflet.navigate (Adw.NavigationDirection.BACK));

            initial_label.activate_link.connect (on_music_folder_clicked);

            _matrix_paintable.paintable = _round_paintable;
            _crossfade_paintable.paintable = _matrix_paintable;
            _crossfade_paintable.queue_draw.connect (music_cover.queue_draw);
            music_cover.paintable = _crossfade_paintable;

            music_album.tooltip_text = _("Search Album");
            music_artist.tooltip_text = _("Search Artist");
            music_title.tooltip_text = _("Search Title");
            make_label_clickable (music_album).released.connect (
                () => win.start_search ("album:" + music_album.label));
            make_label_clickable (music_artist).released.connect (
                () => win.start_search ("artist:" + music_artist.label));
            make_label_clickable (music_title).released.connect (
                () => win.start_search ("title:" + music_title.label));
            make_right_clickable (music_box, show_popover_menu);

            Idle.add (() => {
                // Delay update info after the window shown to avoid slowing down it showing
                if (root.get_height () > 0 && _current_music != _app.current_music) {
                    update_music_info (_app.current_music);
                }
                return root.get_height () == 0;
            }, Priority.LOW);

            app.music_changed.connect (on_music_changed);
            app.music_list.items_changed.connect (on_music_items_changed);
            app.music_tag_parsed.connect (on_music_tag_parsed);
            app.player.state_changed.connect (on_player_state_changed);

            var settings = app.settings;
            settings.bind ("rotate-cover", this, "rotate-cover", SettingsBindFlags.DEFAULT);
            settings.bind ("show-peak", this, "show-peak", SettingsBindFlags.DEFAULT);
        }

        public bool rotate_cover {
            get {
                return _rotate_cover;
            }
            set {
                _rotate_cover = value;
                _round_paintable.ratio = value ? 0.5 : 0.05;
                _matrix_paintable.rotation = value ? _play_bar.position * _degrees_per_second : 0;
                on_player_state_changed (_app.player.state);
            }
        }

        public bool show_peak {
            get {
                return _show_peak;
            }
            set {
                _show_peak = value;
                on_player_state_changed (_app.player.state);
            }
        }

        private Music? _current_music = new Music.empty ();

        private void on_music_changed (Music? music) {
            _current_music = music;
            update_music_info (music);
            root.action_set_enabled (ACTION_APP + ACTION_PLAY, music != null);
        }

        private bool on_music_folder_clicked (string uri) {
            pick_music_folder_async.begin (_app, _app.active_window,
                (dir) => update_initial_label (dir.get_uri ()),
                (obj, res) => pick_music_folder_async.end (res));
            return true;
        }

        private void on_music_items_changed (uint position, uint removed, uint added) {
            var visible = _app.current_music == null && _app.music_store.size == 0
                        && !_app.is_loading_store;
            initial_label.visible = visible;
            if (visible)
                update_initial_label (_app.music_folder);
        }

        private async void on_music_tag_parsed (Music music, Gst.Sample? image) {
            Gdk.Pixbuf? pixbuf = null;
            Gdk.Paintable? paintable = null;
            var thumbnailer = _app.thumbnailer;
            if (image != null) {
                pixbuf = yield run_async<Gdk.Pixbuf?> (
                    () => load_clamp_pixbuf_from_sample ((!)image, _cover_size), true);
                if (pixbuf != null)
                    paintable = Gdk.Texture.for_pixbuf ((!)pixbuf);
            } else {
                paintable = yield thumbnailer.load_async (music, _cover_size);
            }
            if (music == _app.current_music) {
                //  Remote thumbnail may not loaded
                if (pixbuf != null && !(thumbnailer.find (music) is Gdk.Texture)) {
                    pixbuf = yield run_async<Gdk.Pixbuf?> (
                        () => create_clamp_pixbuf ((!)pixbuf, Thumbnailer.ICON_SIZE)
                    );
                    if (pixbuf != null && music == _app.current_music) {
                        thumbnailer.put (music, Gdk.Texture.for_pixbuf ((!)pixbuf), true);
                        _app.music_list.items_changed (_app.current_item, 0, 0);
                    }
                }

                if (music == _app.current_music) {
                    if (paintable == null)
                        paintable = thumbnailer.create_album_text_paintable (music);
                    update_cover_paintables (music, paintable);
                    yield _app.parse_music_cover_async ();
                }
            }
        }

        private Adw.Animation? _scale_animation = null;
        private uint _tick_handler = 0;
        private int64 _tick_last_time = 0;

        private void on_player_state_changed (Gst.State state) {
            var playing = state == Gst.State.PLAYING;
            if (state >= Gst.State.PAUSED) {
                var target = new Adw.CallbackAnimationTarget ((value) => _matrix_paintable.scale = value);
                _scale_animation?.pause ();
                _scale_animation = new Adw.TimedAnimation (music_cover, _matrix_paintable.scale,
                                        _rotate_cover || playing ? 1 : 0.85, 500, target);
                _scale_animation?.play ();
            }

            var need_tick = _rotate_cover || _show_peak;
            if (need_tick && playing && _tick_handler == 0) {
                _tick_last_time = get_monotonic_time ();
                _tick_handler = add_tick_callback (on_tick_callback);
            } else if ((!need_tick || !playing) && _tick_handler != 0) {
                remove_tick_callback (_tick_handler);
                _tick_handler = 0;
            }
        }

        private void on_position_seeked (double pos) {
            if (_rotate_cover)
                _matrix_paintable.rotation = pos * _degrees_per_second;
        }

        private bool on_tick_callback (Gtk.Widget widget, Gdk.FrameClock clock) {
            if (_rotate_cover) {
                var now = get_monotonic_time ();
                var elapsed = (now - _tick_last_time) / 1e6;
                var angle = elapsed * _degrees_per_second;
                _matrix_paintable.rotation += angle;
                _tick_last_time = now;
            }
            if (_show_peak) {
                var peak = _app.player.peak;
                _play_bar.peak = peak;
            }
            return true;
        }

        private void show_popover_menu (double x, double y) {
            var music = _app.current_music;
            if (music != null) {
                var popover = create_music_popover_menu ((!)music, x, y, 
                                false, _app.current_cover != null);
                popover.set_parent (music_box);
                popover.popup ();
            }
        }

        private void update_music_info (Music? music) {
            var empty = music == null && _app.music_store.size == 0;
            if (empty) {
                update_cover_paintables (music, _app.icon);
            }

            music_album.visible = !empty;
            music_artist.visible = !empty;
            music_title.visible = !empty;
            music_album.label = music?.album ?? "";
            music_artist.label = music?.artist ?? "";
            music_title.label = music?.title ?? "";

            var win = _app.active_window;
            if (win is Window)
                ((!)win).title = music?.get_artist_and_title () ?? _app.name;
        }

        private void update_cover_paintables (Music? music, Gdk.Paintable? paintable) {
            _round_paintable = new RoundPaintable (paintable);
            _round_paintable.ratio = _rotate_cover ? 0.5 : 0.05;
            _round_paintable.queue_draw.connect (music_cover.queue_draw);
            _matrix_paintable = new MatrixPaintable (_round_paintable);
            _matrix_paintable.queue_draw.connect (music_cover.queue_draw);
            _crossfade_paintable.paintable = _matrix_paintable;
            cover_changed (music, _crossfade_paintable);
        }

        private void update_initial_label (string uri) {
            var dir_name = get_display_name (uri);
            var link = @"<a href=\"change_dir\">$dir_name</a>";
            initial_label.set_markup (_("Drag and drop music files here,\nor change music location: ") + link);
        }
    }
}
