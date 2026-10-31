/*
 * Interstellar title bars for Qt apps on Wayland.
 *
 * Derived from QAdwaitaDecorations 0.1.7
 * (https://github.com/FedoraQt/QAdwaitaDecorations), the client-side
 * decorations Qt Wayland also bundles as its "adwaita" plugin.
 * Copyright (C) 2023 Jan Grulich <jgrulich@redhat.com>
 * Copyright (C) 2026 Mariano Miguel (Interstellar's bar: two lights at the
 * start, the theme's colours from kdeglobals, no minimize)
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
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA
 */

#ifndef INTERSTELLAR_DECORATION_H
#define INTERSTELLAR_DECORATION_H

#include "palette.h"

#include <QtWaylandClient/private/qwaylandabstractdecoration_p.h>

#include <QtCore/QLoggingCategory>
#include <QtCore/QPointer>
#include <QtCore/QTimer>

Q_DECLARE_LOGGING_CATEGORY(lcInterstellarDecoration)

namespace QtWaylandClient {
class QWaylandInputDevice;
}

namespace Interstellar {

// The title bar: the theme's window colour, the title centred in its text
// colour, and two lights at the start, close (red) then maximize (green);
// niri has no minimize. Glyphs show while the pointer is over the lights; both
// lights go grey while the window is not focused.
class Decoration : public QtWaylandClient::QWaylandAbstractDecoration
{
    Q_OBJECT
public:
    Decoration();

protected:
    QMargins margins(MarginsType marginsType = Full) const override;
    void paint(QPaintDevice *device) override;
    bool handleMouse(QtWaylandClient::QWaylandInputDevice *inputDevice, const QPointF &local,
                     const QPointF &global, Qt::MouseButtons buttons,
                     Qt::KeyboardModifiers mods) override;
    bool handleTouch(QtWaylandClient::QWaylandInputDevice *inputDevice, const QPointF &local,
                     const QPointF &global, QEventPoint::State state,
                     Qt::KeyboardModifiers mods) override;

private:
    enum Light { None, Close, Maximize };

    bool isActive() const;
    bool isMaximized() const;
    bool isSquare() const;
    bool canMaximize() const;

    QRectF bar() const;
    QRectF lightRect(Light light) const; // the 12 px circle
    QRectF lightTarget(Light light) const; // where a click lands
    QRectF lightsArea() const; // hovering it shows the glyphs
    Light lightAt(const QPointF &local) const;

    void paintLight(QPainter &painter, Light light, const Palette::Colors &colors,
                    bool active) const;

    void handleBar(QtWaylandClient::QWaylandInputDevice *inputDevice, const QPointF &local,
                   Qt::MouseButtons buttons);
    void resizeFrom(QtWaylandClient::QWaylandInputDevice *inputDevice, Qt::Edges edges,
                    Qt::MouseButtons buttons);
    bool isDoubleClick(const QPointF &local);
    void activate(Light light);
    void setLightsHovered(bool hovered, QtWaylandClient::QWaylandInputDevice *inputDevice);
    void checkPointer();
    void requestRepaint();

    QPointer<Palette> m_palette;

    Light m_pressed = None;
    bool m_lightsHovered = false;
    // The decoration hears no pointer leave; while the lights are hovered,
    // poll whether the pointer is still on this window.
    QPointer<QtWaylandClient::QWaylandInputDevice> m_hoverDevice;
    QTimer m_hoverCheck;

    bool m_logged = false;
    qint64 m_lastClick = 0;
    QPointF m_lastClickPosition;
};

} // namespace Interstellar

#endif
