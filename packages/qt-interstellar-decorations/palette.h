/*
 * Interstellar title bars for Qt apps on Wayland: the theme they paint with.
 *
 * Copyright (C) 2026 Mariano Miguel
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 */

#ifndef INTERSTELLAR_PALETTE_H
#define INTERSTELLAR_PALETTE_H

#include <QtCore/QByteArray>
#include <QtCore/QFileSystemWatcher>
#include <QtCore/QMutex>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QTimer>
#include <QtGui/QColor>
#include <QtGui/QFont>

namespace Interstellar {

// The bar's colours and font come from what themeport writes for every app on
// each theme switch: its KDE colour scheme (~/.config/kdeglobals, the
// [Colors:Header] or [Colors:Window] group) for the bar and its title, and its
// GTK 3 palette (~/.config/gtk-3.0/gtk.css: light_close, light_zoom,
// light_idle) for the lights, so Qt's lights are the GTK apps'. Without that
// palette the lights follow azure-folio's selection (Folio or Lumen). One
// palette serves every window of the process. It reloads when a file changes
// and checks them again whenever a title bar repaints (focus changes repaint
// it), so a theme switch reaches running apps without a restart.
class Palette : public QObject
{
    Q_OBJECT
public:
    struct Colors
    {
        QColor bar;
        QColor text;
        QColor textInactive;
        QColor close;
        QColor maximize;
        QColor idle; // both lights while the window is not focused
        QFont font;
    };

    // Created on the GUI thread (decorations are), parented to the app.
    static Palette *instance();

    // Safe from any thread (Qt Quick windows paint their bar on the render thread).
    Colors colors() const;

    // GUI thread only: reloads if either file changed since it was last read.
    void refresh();

Q_SIGNALS:
    void changed();

private:
    explicit Palette(QObject *parent);
    void load();
    void watch();
    QByteArray stamp() const;

    QString m_kdeglobals;
    QString m_gtkCss;
    QString m_selection;
    QByteArray m_stamp;
    QFileSystemWatcher m_watcher;
    QTimer m_settle;

    mutable QMutex m_mutex;
    Colors m_colors;
};

} // namespace Interstellar

#endif
