#!/usr/bin/env python3
"""
Запускается в GitHub Actions ПОСЛЕ `flutter create` (генерирует чистый
Android-скаффолд с актуальными под версию рантайм-Flutter файлами Gradle)
и ПОСЛЕ того как lib/ и android_overlay/ скопированы поверх.

Делает две точечные правки, которые невозможно сделать простым cp,
потому что формат генерируемых Flutter'ом файлов может немного
отличаться между версиями:

1. Добавляет в pubspec.yaml наши дополнительные зависимости
   (shared_preferences, intl, provider) из pubspec_extra.yaml.
2. Добавляет в android/app/build.gradle(.kts) зависимость
   androidx.window:window — она нужна для Jetpack Activity Embedding
   (CarLauncherApplication.kt) и не входит в стандартный шаблон Flutter.

Использование: python3 scripts/patch_project.py <путь-к-сгенерированному-проекту>
"""
import re
import sys
import pathlib

def fail(message: str) -> None:
    print(f"patch_project.py: {message}", file=sys.stderr)
    sys.exit(1)

def main() -> None:
    if len(sys.argv) != 2:
        fail("ожидается один аргумент — путь к проекту, сгенерированному flutter create")

    target = pathlib.Path(sys.argv[1])
    repo_root = pathlib.Path(__file__).resolve().parent.parent

    # ---- 1. pubspec.yaml: добавить наши зависимости ----
    pubspec_path = target / "pubspec.yaml"
    if not pubspec_path.exists():
        fail(f"{pubspec_path} не найден")

    lines = pubspec_path.read_text(encoding="utf-8").splitlines()
    extra_lines = (repo_root / "pubspec_extra.yaml").read_text(encoding="utf-8").splitlines()

    insert_at = None
    for i, line in enumerate(lines):
        if line.strip() == "sdk: flutter":
            insert_at = i + 1
            break
    if insert_at is None:
        fail("не нашёл строку 'sdk: flutter' в сгенерированном pubspec.yaml — "
             "формат шаблона Flutter мог измениться, добавьте зависимости вручную")

    lines[insert_at:insert_at] = extra_lines
    pubspec_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"pubspec.yaml: добавлены {len(extra_lines)} строк зависимостей")

    # ---- 2. android/app/build.gradle(.kts): добавить androidx.window ----
    patched = False
    for name in ("build.gradle.kts", "build.gradle"):
        gradle_path = target / "android" / "app" / name
        if not gradle_path.exists():
            continue
        content = gradle_path.read_text(encoding="utf-8")
        new_content, count = re.subn(
            r"dependencies\s*\{",
            'dependencies {\n    implementation("androidx.window:window:1.3.0")',
            content,
            count=1,
        )
        if count == 0:
            fail(f"не нашёл блок 'dependencies {{' в {gradle_path}")
        gradle_path.write_text(new_content, encoding="utf-8")
        print(f"{name}: добавлена зависимость androidx.window:window:1.3.0")
        patched = True
        break

    if not patched:
        fail("не нашёл android/app/build.gradle(.kts) — структура проекта неожиданная")

if __name__ == "__main__":
    main()
