/*
 * Interstellar title bars for Qt apps on Wayland: the plugin.
 *
 * Derived from QAdwaitaDecorations 0.1.7
 * (https://github.com/FedoraQt/QAdwaitaDecorations).
 * Copyright (C) 2023 Jan Grulich <jgrulich@redhat.com>
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
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA
 */

#include "decoration.h"

#include <QtWaylandClient/private/qwaylanddecorationfactory_p.h>
#include <QtWaylandClient/private/qwaylanddecorationplugin_p.h>

using namespace QtWaylandClient;

Q_LOGGING_CATEGORY(lcInterstellarDecoration, "qt.qpa.wayland.interstellar", QtWarningMsg)

namespace Interstellar {

class DecorationPlugin : public QWaylandDecorationPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QWaylandDecorationFactoryInterface_iid FILE "interstellar.json")
public:
    QWaylandAbstractDecoration *create(const QString &key, const QStringList &params) override
    {
        if (key.compare(QLatin1String("interstellar"), Qt::CaseInsensitive) != 0)
            return nullptr;
        // Decorations are private Qt API, kept only by the exact Qt this was
        // built against. An app on another Qt (Qt loads plugins from older
        // minor versions) gets Qt's own title bar instead of a crash.
        if (qstrcmp(qVersion(), QT_VERSION_STR) != 0) {
            qCWarning(lcInterstellarDecoration,
                      "built for Qt %s, running on Qt %s: using Qt's default title bar",
                      QT_VERSION_STR, qVersion());
            return QWaylandDecorationFactory::create(QStringLiteral("bradient"), params);
        }
        return new Decoration;
    }
};

} // namespace Interstellar

#include "plugin.moc"
