# Підписун (pidpisun)

Десктопна програма для **підписів і печаток** на PDF/DOCX. Працює на **macOS** і **Windows** (Flutter UI + Python-рушій для штампування).

## Що робить

- Відкриває **PDF** і **DOCX** (DOCX конвертується перед роботою)
- Зліва — файловий менеджер і бібліотека PNG-печаток / підписів
- Перетягуєте печатку на сторінку документа, крутите, міняєте розмір (мм), прозорість і колір
- Зберігаєте результат у **новий PDF**
- Печатки зберігаються в одному портативному файлі `pechatky.podpisun` (зручно носити на флешці разом із програмою)

## Особливості

- Світла / темна тема
- Закріплені папки в лівій панелі
- Drag & drop документів і PNG
- Портативна збірка: exe/app + печатки поруч, без обов’язкової установки
- Окремий Python engine (PyMuPDF тощо) для надійного накладання штампів

## Завантаження

Готові файли в репозиторії — тека [`dist/`](dist/):

| Файл | Що це |
|---|---|
| `Pidpysun-1.0.0-macos.dmg` | інсталятор macOS |
| `Pidpysun-1.0.0-macos-portable.zip` | portable macOS |
| `Pidpysun-1.0.0-windows-setup.exe` | інсталятор Windows |
| `Pidpysun-1.0.0-windows-portable.zip` | portable Windows (exe в архіві) |

Також: [Releases](https://github.com/Metel-Sky/pidpisun/releases).

## Запуск з коду

```bash
# UI
flutter pub get
flutter run -d macos   # або windows

# Python-рушій (розробка)
python3 -m venv engine/.venv
engine/.venv/bin/pip install -r engine/requirements.txt
```

Збірка інсталяторів: `tool/package_macos.sh`, `tool/package_windows.ps1`.

## Стек

Flutter · Riverpod · pdfrx · Python (PyMuPDF) · Inno Setup (Windows)
