/*
 * Interstellar title bars for Qt apps on Wayland.
 *
 * Derived from QAdwaitaDecorations 0.1.7
 * (https://github.com/FedoraQt/QAdwaitaDecorations), the client-side
 * decorations Qt Wayland also bundles as its "adwaita" plugin: the margins,
 * resize edges, title-bar mouse handling and repaint requests follow it.
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

#include "decoration.h"

#include <QtWaylandClient/private/qwaylandinputdevice_p.h>
#include <QtWaylandClient/private/qwaylandshellsurface_p.h>
#include <QtWaylandClient/private/qwaylandwindow_p.h>

#include <QtCore/QDateTime>
#include <QtCore/QThread>
#include <QtGui/QFontMetricsF>
#include <QtGui/QGuiApplication>
#include <QtGui/QPainter>
#include <QtGui/QPainterPath>
#include <QtGui/QPolygonF>
#include <QtGui/QStyleHints>
#include <QtGui/qpa/qwindowsysteminterface.h>

using namespace QtWaylandClient;

namespace Interstellar {

namespace {

// Measured from the GTK title bars (libadwaita header bar with the lights) so
// bars line up across apps: 46 px tall, 12 px lights 9 px apart, the first one
// 9 px from the window's edge.
constexpr int titlebarHeight = 46;
constexpr qreal lightSize = 12;
constexpr qreal lightGap = 9;
constexpr qreal lightInset = 9;
// Around the lights, the band where the pointer shows the glyphs.
constexpr qreal lightSlack = 6;
// Only for compositors that do not tile the window (niri always says tiled):
// an invisible band to resize from, a hairline frame and niri's corner radius.
constexpr int resizeBand = 10;
constexpr int borderWidth = 1;
constexpr qreal cornerRadius = 12;

QPainterPath roundedTop(const QRectF &rect, qreal radius)
{
    QPainterPath path;
    path.moveTo(rect.bottomLeft());
    path.lineTo(rect.left(), rect.top() + radius);
    path.arcTo(QRectF(rect.topLeft(), QSizeF(2 * radius, 2 * radius)), 180, -90);
    path.lineTo(rect.right() - radius, rect.top());
    path.arcTo(QRectF(rect.right() - 2 * radius, rect.top(), 2 * radius, 2 * radius), 90, -90);
    path.lineTo(rect.bottomRight());
    path.closeSubpath();
    return path;
}

} // namespace

Decoration::Decoration()
    : m_palette(Palette::instance())
{
    m_hoverCheck.setInterval(150);
    connect(&m_hoverCheck, &QTimer::timeout, this, &Decoration::checkPointer);
    connect(m_palette, &Palette::changed, this, &Decoration::requestRepaint);
}

bool Decoration::isActive() const
{
    return waylandWindow()->windowStates().testFlag(Qt::WindowActive);
}

bool Decoration::isMaximized() const
{
    return waylandWindow()->windowStates().testFlag(Qt::WindowMaximized);
}

bool Decoration::isSquare() const
{
    return isMaximized()
            || waylandWindow()->toplevelWindowTilingStates() != QWaylandWindow::WindowNoState;
}

// Like GTK: no maximize light on fixed-size windows, nor on dialogs unless
// they ask for one. (Main windows' button hints are unreliable: Dolphin's
// carry none, so only dialogs read them.)
bool Decoration::canMaximize() const
{
    const QWindow *qwindow = window();
    if (!qwindow)
        return true;
    if (qwindow->minimumSize() == qwindow->maximumSize())
        return false;
    switch (qwindow->type()) {
    case Qt::Dialog:
    case Qt::Sheet:
    case Qt::Tool:
        return qwindow->flags().testFlag(Qt::WindowMaximizeButtonHint);
    default:
        return true;
    }
}

QMargins Decoration::margins(MarginsType marginsType) const
{
    if (isMaximized())
        return QMargins(0, marginsType == ShadowsOnly ? 0 : titlebarHeight, 0, 0);

    const QWaylandWindow::ToplevelWindowTilingStates tiling =
            waylandWindow()->toplevelWindowTilingStates();
    const int around = marginsType == ShadowsOnly ? resizeBand
            : marginsType == ShadowsExcluded      ? borderWidth
                                                  : resizeBand + borderWidth;
    const auto side = [&](QWaylandWindow::ToplevelWindowTilingState edge) {
        return tiling.testFlag(edge) ? 0 : around;
    };
    return QMargins(side(QWaylandWindow::WindowTiledLeft),
                    side(QWaylandWindow::WindowTiledTop)
                            + (marginsType == ShadowsOnly ? 0 : titlebarHeight),
                    side(QWaylandWindow::WindowTiledRight),
                    side(QWaylandWindow::WindowTiledBottom));
}

QRectF Decoration::bar() const
{
    const QMargins full = margins();
    const QSize size = waylandWindow()->surfaceSize();
    return QRectF(full.left(), full.top() - titlebarHeight,
                  size.width() - full.left() - full.right(), titlebarHeight);
}

QRectF Decoration::lightRect(Light light) const
{
    const QRectF titlebar = bar();
    const int index = light == Maximize ? 1 : 0;
    return QRectF(titlebar.left() + lightInset + index * (lightSize + lightGap),
                  titlebar.top() + (titlebar.height() - lightSize) / 2, lightSize, lightSize);
}

QRectF Decoration::lightTarget(Light light) const
{
    return lightRect(light).adjusted(-lightGap / 2, -lightSlack, lightGap / 2, lightSlack);
}

QRectF Decoration::lightsArea() const
{
    QRectF area = lightTarget(Close);
    if (canMaximize())
        area |= lightTarget(Maximize);
    return area;
}

Decoration::Light Decoration::lightAt(const QPointF &local) const
{
    if (lightTarget(Close).contains(local))
        return Close;
    if (canMaximize() && lightTarget(Maximize).contains(local))
        return Maximize;
    return None;
}

void Decoration::paint(QPaintDevice *device)
{
    // Qt Quick windows paint this on their render thread; the palette is
    // reloaded on the GUI thread only.
    if (m_palette && QThread::isMainThread())
        m_palette->refresh();
    const Palette::Colors colors = m_palette ? m_palette->colors() : Palette::Colors();
    const bool active = isActive();

    const QSizeF size = waylandWindow()->surfaceSize();
    const QRectF frame =
            QRectF(QPointF(), size).marginsRemoved(QMarginsF(margins(ShadowsOnly)));

    QPainter painter(device);
    painter.setRenderHint(QPainter::Antialiasing);

    if (isSquare()) {
        // niri tiles every window and rounds its corners itself.
        painter.fillRect(frame, colors.bar);
    } else {
        painter.fillPath(roundedTop(frame, cornerRadius), colors.bar);
        QColor hairline = colors.text;
        hairline.setAlphaF(0.12);
        painter.strokePath(roundedTop(frame.adjusted(0.5, 0.5, -0.5, -0.5), cornerRadius - 0.5),
                           QPen(hairline, 1));
    }

    // The title, centred on the whole bar and kept clear of the lights.
    const QString title = waylandWindow()->windowTitle();
    if (!title.isEmpty()) {
        const QRectF titlebar = bar();
        const qreal clear = lightsArea().right() - titlebar.left() + 8;
        const QRectF room = titlebar.adjusted(clear, 0, -clear, 0);
        if (room.width() > 0) {
            const QFontMetricsF metrics(colors.font, device);
            painter.setFont(colors.font);
            painter.setPen(active ? colors.text : colors.textInactive);
            painter.drawText(room, Qt::AlignCenter | Qt::TextSingleLine,
                             metrics.elidedText(title, Qt::ElideRight, room.width()));
        }
    }

    if (!m_logged) {
        m_logged = true;
        qCDebug(lcInterstellarDecoration) << window() << window()->flags() << window()->type()
                                          << window()->minimumSize() << window()->maximumSize()
                                          << "maximize" << canMaximize() << "tiling"
                                          << waylandWindow()->toplevelWindowTilingStates();
    }
    paintLight(painter, Close, colors, active);
    if (canMaximize())
        paintLight(painter, Maximize, colors, active);
}

void Decoration::paintLight(QPainter &painter, Light light, const Palette::Colors &colors,
                            bool active) const
{
    const QRectF rect = lightRect(light);
    // Grey while the window is not focused, unless the pointer is on the lights.
    const bool lit = active || m_lightsHovered;
    QColor fill = lit ? (light == Close ? colors.close : colors.maximize) : colors.idle;
    if (m_pressed == light)
        fill = fill.darker(125);

    painter.save();
    painter.setPen(Qt::NoPen);
    painter.setBrush(fill);
    painter.drawEllipse(rect);
    if (lit) {
        // The GTK lights' faint inner edge: inset 1 px, black at 14 %.
        painter.setBrush(Qt::NoBrush);
        painter.setPen(QPen(QColor(0, 0, 0, 36), 1));
        painter.drawEllipse(rect.adjusted(0.5, 0.5, -0.5, -0.5));
    }
    if (m_lightsHovered) {
        const QColor glyph(0, 0, 0, 153); // black at 60 %, as on the GTK lights
        const QPointF centre = rect.center();
        if (light == Close) {
            // One path, so the translucent strokes do not darken where they cross.
            const qreal arm = 2.4;
            QPainterPath cross;
            cross.moveTo(centre + QPointF(-arm, -arm));
            cross.lineTo(centre + QPointF(arm, arm));
            cross.moveTo(centre + QPointF(-arm, arm));
            cross.lineTo(centre + QPointF(arm, -arm));
            painter.setBrush(Qt::NoBrush);
            painter.setPen(QPen(glyph, 1.3, Qt::SolidLine, Qt::RoundCap));
            painter.drawPath(cross);
        } else {
            // Two arrowheads on the diagonal: outward to maximize, inward to restore.
            painter.setPen(Qt::NoPen);
            painter.setBrush(glyph);
            const bool restore = isMaximized();
            for (const qreal s : { -1.0, 1.0 }) {
                QPolygonF arrowhead;
                if (restore)
                    arrowhead << centre + QPointF(0.5 * s, 0.5 * s)
                              << centre + QPointF(0.5 * s, 4.0 * s)
                              << centre + QPointF(4.0 * s, 0.5 * s);
                else
                    arrowhead << centre + QPointF(3.0 * s, 3.0 * s)
                              << centre + QPointF(-0.6 * s, 3.0 * s)
                              << centre + QPointF(3.0 * s, -0.6 * s);
                painter.drawPolygon(arrowhead);
            }
        }
    }
    painter.restore();
}

bool Decoration::handleMouse(QWaylandInputDevice *inputDevice, const QPointF &local,
                             const QPointF &global, Qt::MouseButtons buttons,
                             Qt::KeyboardModifiers mods)
{
    Q_UNUSED(global)
    Q_UNUSED(mods)

    const QMargins full = margins();
    const QSize size = waylandWindow()->surfaceSize();
    const int barTop = full.top() - titlebarHeight; // above it: the resize band
    const qreal x = local.x();
    const qreal y = local.y();
    const auto withCorner = [&](Qt::Edges edges) {
        if (x < full.left())
            edges |= Qt::LeftEdge;
        else if (x >= size.width() - full.right())
            edges |= Qt::RightEdge;
        return edges;
    };

    if (y < barTop) {
        setLightsHovered(false, nullptr);
        resizeFrom(inputDevice, withCorner(Qt::TopEdge), buttons);
    } else if (y >= size.height() - full.bottom()) {
        setLightsHovered(false, nullptr);
        resizeFrom(inputDevice, withCorner(Qt::BottomEdge), buttons);
    } else if (x < full.left()) {
        setLightsHovered(false, nullptr);
        resizeFrom(inputDevice, Qt::LeftEdge, buttons);
    } else if (x >= size.width() - full.right()) {
        setLightsHovered(false, nullptr);
        resizeFrom(inputDevice, Qt::RightEdge, buttons);
    } else if (y < full.top()) {
        handleBar(inputDevice, local, buttons);
    } else {
        setLightsHovered(false, nullptr);
#if QT_CONFIG(cursor)
        waylandWindow()->restoreMouseCursor(inputDevice);
#endif
    }

    // A press that ends away from the light it started on does nothing.
    if (isLeftReleased(buttons) && m_pressed != None) {
        m_pressed = None;
        requestRepaint();
    }

    setMouseButtons(buttons);
    return false;
}

void Decoration::handleBar(QWaylandInputDevice *inputDevice, const QPointF &local,
                           Qt::MouseButtons buttons)
{
#if QT_CONFIG(cursor)
    waylandWindow()->restoreMouseCursor(inputDevice);
#endif
    setLightsHovered(lightsArea().contains(local), inputDevice);
    const Light light = lightAt(local);

    if (isLeftClicked(buttons) && light != None) {
        m_pressed = light;
        requestRepaint();
        return;
    }
    if (m_pressed != None) {
        if (isLeftReleased(buttons)) {
            const Light pressed = m_pressed;
            m_pressed = None;
            requestRepaint();
            if (pressed == light)
                activate(light);
        }
        return;
    }
    if (isLeftClicked(buttons) && isDoubleClick(local)) {
        if (canMaximize())
            activate(Maximize);
        return;
    }
    if (isRightClicked(buttons)) {
        showWindowMenu(inputDevice);
        return;
    }
    startMove(inputDevice, buttons);
}

bool Decoration::handleTouch(QWaylandInputDevice *inputDevice, const QPointF &local,
                             const QPointF &global, QEventPoint::State state,
                             Qt::KeyboardModifiers mods)
{
    Q_UNUSED(global)
    Q_UNUSED(mods)

    if (state != QEventPoint::Pressed)
        return false;
    if (const Light light = lightAt(local); light != None) {
        activate(light);
        return true;
    }
    if (local.y() < margins().top()) {
        if (QWaylandShellSurface *shell = waylandWindow()->shellSurface())
            shell->move(inputDevice);
        return true;
    }
    return false;
}

void Decoration::resizeFrom(QWaylandInputDevice *inputDevice, Qt::Edges edges,
                            Qt::MouseButtons buttons)
{
#if QT_CONFIG(cursor)
    Qt::CursorShape shape = Qt::SizeVerCursor;
    if (edges == (Qt::TopEdge | Qt::LeftEdge) || edges == (Qt::BottomEdge | Qt::RightEdge))
        shape = Qt::SizeFDiagCursor;
    else if (edges == (Qt::TopEdge | Qt::RightEdge) || edges == (Qt::BottomEdge | Qt::LeftEdge))
        shape = Qt::SizeBDiagCursor;
    else if (edges & (Qt::LeftEdge | Qt::RightEdge))
        shape = Qt::SizeHorCursor;
    waylandWindow()->applyCursor(inputDevice, shape);
#endif
    startResize(inputDevice, edges, buttons);
}

bool Decoration::isDoubleClick(const QPointF &local)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const QStyleHints *hints = QGuiApplication::styleHints();
    const bool isDouble = now - m_lastClick <= hints->mouseDoubleClickInterval()
            && (local - m_lastClickPosition).manhattanLength() <= hints->mouseDoubleClickDistance();
    m_lastClick = isDouble ? 0 : now;
    m_lastClickPosition = local;
    return isDouble;
}

void Decoration::activate(Light light)
{
    if (light == Close) {
        setLightsHovered(false, nullptr);
        QWindowSystemInterface::handleCloseEvent(window());
    } else if (light == Maximize) {
        window()->setWindowStates(window()->windowStates() ^ Qt::WindowMaximized);
    }
}

void Decoration::setLightsHovered(bool hovered, QWaylandInputDevice *inputDevice)
{
    if (hovered)
        m_hoverDevice = inputDevice;
    if (hovered == m_lightsHovered)
        return;
    m_lightsHovered = hovered;
    if (hovered)
        m_hoverCheck.start();
    else
        m_hoverCheck.stop();
    requestRepaint();
}

void Decoration::checkPointer()
{
    if (m_hoverDevice && m_hoverDevice->pointerFocus() == waylandWindow())
        return;
    m_pressed = None;
    setLightsHovered(false, nullptr);
}

void Decoration::requestRepaint()
{
    update();
    if (QWindow *qwindow = window())
        qwindow->requestUpdate();
}

} // namespace Interstellar
