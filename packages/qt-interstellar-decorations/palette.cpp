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

#include "palette.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QMutexLocker>
#include <QtCore/QPointer>
#include <QtCore/QRegularExpression>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>
#include <QtCore/QStringList>

namespace Interstellar {

namespace {

// Each theme's lights when themeport's GTK palette is missing: close,
// maximize, and the grey of both while the window is not focused, as
// tools/azure-folio/looks.py gives them (light_close, light_zoom, light_idle).
struct Lights
{
    QRgb close;
    QRgb maximize;
    QRgb idle;
};
constexpr Lights lumenLight{ 0xff5f57, 0x28c840, 0xd1d1d6 };
constexpr Lights lumenDark{ 0xff5f57, 0x28c840, 0x48484a };
constexpr Lights folioLight{ 0xb4473f, 0x3f7d5c, 0xd9d0bf };
constexpr Lights folioDark{ 0xf09088, 0x8cc5a3, 0x263e5e };

// KDE writes colours as "r,g,b" (QSettings reads that as a list); #rrggbb is
// accepted too.
QColor parseColor(const QVariant &value)
{
    QStringList parts = value.toStringList();
    if (parts.size() == 1)
        parts = parts.first().split(QLatin1Char(','));
    if (parts.size() == 3 || parts.size() == 4) {
        int channel[4] = { 0, 0, 0, 255 };
        bool ok = true;
        for (int i = 0; i < parts.size() && ok; ++i) {
            channel[i] = parts.at(i).trimmed().toInt(&ok);
            ok = ok && channel[i] >= 0 && channel[i] <= 255;
        }
        if (ok)
            return QColor(channel[0], channel[1], channel[2], channel[3]);
    }
    if (parts.size() == 1)
        return QColor::fromString(parts.first().trimmed());
    return QColor();
}

QColor kdeColor(QSettings &kde, QLatin1StringView key)
{
    for (const QLatin1StringView group : { QLatin1StringView("Colors:Header"),
                                           QLatin1StringView("Colors:Window") }) {
        const QColor color = parseColor(kde.value(QString(group) + QLatin1Char('/') + key));
        if (color.isValid())
            return color;
    }
    return QColor();
}

// Relative luminance (sRGB weights): a dark bar means the dark mode's lights.
bool isDark(const QColor &color)
{
    return 0.2126 * color.redF() + 0.7152 * color.greenF() + 0.0722 * color.blueF() < 0.5;
}

QColor mix(const QColor &a, const QColor &b, qreal t)
{
    return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t,
                            a.greenF() + (b.greenF() - a.greenF()) * t,
                            a.blueF() + (b.blueF() - a.blueF()) * t);
}

// themeport's GTK 3 palette names the lights: @define-color light_close #rrggbb;
QColor gtkColor(const QString &css, QLatin1StringView name)
{
    const QRegularExpression define(QStringLiteral("@define-color\\s+") + name
                                    + QStringLiteral("\\s+(#[0-9a-fA-F]{6})\\s*;"));
    const QRegularExpressionMatch match = define.match(css);
    return match.hasMatch() ? QColor::fromString(match.captured(1)) : QColor();
}

QPointer<Palette> s_instance;

} // namespace

Palette *Palette::instance()
{
    if (!s_instance)
        s_instance = new Palette(QCoreApplication::instance());
    return s_instance;
}

Palette::Palette(QObject *parent)
    : QObject(parent)
    , m_kdeglobals(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                   + QLatin1String("/kdeglobals"))
    , m_gtkCss(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
               + QLatin1String("/gtk-3.0/gtk.css"))
    // Where azure-folio keeps the chosen theme (tools/azure-folio/azure_folio.py).
    , m_selection(QDir::homePath()
                  + QLatin1String("/.local/state/nixos-config/azure-folio/selection.json"))
{
    // Theme switches rewrite many files at once; read them once they settle.
    m_settle.setSingleShot(true);
    m_settle.setInterval(150);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_settle, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_settle,
            qOverload<>(&QTimer::start));
    connect(&m_settle, &QTimer::timeout, this, [this] {
        watch();
        refresh();
    });
    load();
    watch();
}

Palette::Colors Palette::colors() const
{
    QMutexLocker locker(&m_mutex);
    return m_colors;
}

void Palette::refresh()
{
    if (stamp() == m_stamp)
        return;
    load();
    Q_EMIT changed();
}

// themeport rewrites its files in place, azure-folio replaces its selection,
// and ~/.config/kdeglobals is a symlink into themeport's state: watch the
// files and the folders they really live in, and add back whatever a
// replacement dropped.
void Palette::watch()
{
    QStringList paths;
    for (const QString &file : { m_kdeglobals, m_gtkCss, m_selection }) {
        const QFileInfo info(file);
        if (!info.exists())
            continue;
        paths << file;
        const QString target = info.canonicalFilePath();
        if (!target.isEmpty())
            paths << QFileInfo(target).absolutePath();
    }
    paths.removeDuplicates();

    const QStringList watched = m_watcher.files() + m_watcher.directories();
    QStringList missing;
    for (const QString &path : std::as_const(paths)) {
        if (!watched.contains(path))
            missing << path;
    }
    if (!missing.isEmpty())
        m_watcher.addPaths(missing);
}

QByteArray Palette::stamp() const
{
    QByteArray stamp;
    for (const QString &file : { m_kdeglobals, m_gtkCss, m_selection }) {
        const QFileInfo info(file); // follows symlinks
        stamp += QByteArray::number(info.exists() ? info.lastModified().toMSecsSinceEpoch() : -1);
        stamp += ':' + QByteArray::number(info.size()) + ':'
                + info.canonicalFilePath().toUtf8() + ';';
    }
    return stamp;
}

void Palette::load()
{
    m_stamp = stamp();

    QSettings kde(m_kdeglobals, QSettings::IniFormat);
    const QColor bar = kdeColor(kde, QLatin1StringView("BackgroundNormal"));
    const QColor text = kdeColor(kde, QLatin1StringView("ForegroundNormal"));
    const QColor textInactive = kdeColor(kde, QLatin1StringView("ForegroundInactive"));

    QString theme;
    QString mode;
    QFile selection(m_selection);
    if (selection.open(QIODevice::ReadOnly)) {
        const QJsonObject object = QJsonDocument::fromJson(selection.readAll()).object();
        theme = object.value(QLatin1String("theme")).toString();
        mode = object.value(QLatin1String("mode")).toString();
    }

    // The bar itself decides the mode, so the lights always suit what they
    // sit on; the selection's mode only stands in when kdeglobals is missing.
    const bool dark = bar.isValid() ? isDark(bar) : mode == QLatin1String("dark");
    const bool lumen = theme == QLatin1String("lumen");
    const Lights &lights = lumen ? (dark ? lumenDark : lumenLight) : (dark ? folioDark : folioLight);

    QString css;
    QFile gtk(m_gtkCss);
    if (gtk.open(QIODevice::ReadOnly))
        css = QString::fromUtf8(gtk.readAll());
    const QColor gtkClose = gtkColor(css, QLatin1StringView("light_close"));
    const QColor gtkZoom = gtkColor(css, QLatin1StringView("light_zoom"));
    const QColor gtkIdle = gtkColor(css, QLatin1StringView("light_idle"));

    Colors colors;
    // Without kdeglobals: Folio's paper and ink.
    colors.bar = bar.isValid() ? bar : QColor(dark ? 0x101d33 : 0xf7f4e9);
    colors.text = text.isValid() ? text : QColor(dark ? 0xe4e9f0 : 0x263a57);
    colors.textInactive = textInactive.isValid() ? textInactive : mix(colors.text, colors.bar, 0.45);
    colors.close = gtkClose.isValid() ? gtkClose : QColor(lights.close);
    colors.maximize = gtkZoom.isValid() ? gtkZoom : QColor(lights.maximize);
    colors.idle = gtkIdle.isValid() ? gtkIdle : QColor(lights.idle);

    // The theme's interface font (Inter), bold like GTK's window titles.
    // QSettings files [General] keys at the top level and splits on commas.
    QVariant font = kde.value(QLatin1String("font"));
    if (!font.isValid())
        font = kde.value(QLatin1String("General/font"));
    colors.font = QFont(QStringLiteral("Inter"), 10);
    const QString spec = font.toStringList().join(QLatin1Char(','));
    if (!spec.isEmpty()) {
        QFont parsed;
        if (parsed.fromString(spec))
            colors.font = parsed;
    }
    colors.font.setWeight(QFont::Bold);

    QMutexLocker locker(&m_mutex);
    m_colors = colors;
}

} // namespace Interstellar
