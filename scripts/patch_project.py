#!/usr/bin/env python3
"""
Запускается в GitHub Actions ПОСЛЕ `flutter create` (генерирует чистый
Android-скаффолд с актуальными под версию рантайм-Flutter файлами Gradle)
и ПОСЛЕ того как lib/ и android_overlay/ скопированы поверх.

Добавляет в сгенерированный pubspec.yaml наши дополнительные зависимости
(shared_preferences, intl, provider) из pubspec_extra.yaml. Простым cp
этого не сделать: формат шаблона pubspec немного отличается между
версиями Flutter.

Использование: python3 scripts/patch_project.py <путь-к-сгенерированному-проекту>
"""
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

    # Принудительные версии плагинов. shared_preferences_android 2.5.0
    # (17.10.2026) перешёл на JNI и падает в release-сборке
    # (NoSuchMethodError getAll) — держим последнюю рабочую 2.4.x.
    (target / "pubspec_overrides.yaml").write_text(
        "dependency_overrides:\n  shared_preferences_android: 2.4.29\n", encoding="utf-8")
    print("pubspec_overrides.yaml: shared_preferences_android закреплён на 2.4.29")


if __name__ == "__main__":
    main()
