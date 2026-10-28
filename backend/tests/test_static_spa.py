"""Unit tests for FastAPI SPA static asset serving."""

import pathlib

from fastapi import testclient

from app import main


def test_spa_root_serves_index_html_when_dist_exists(
    tmp_path: pathlib.Path,
) -> None:
    """Verifies GET / serves index.html when static dist directory exists."""
    dist_dir = tmp_path / "dist"
    assets_dir = dist_dir / "assets"
    assets_dir.mkdir(parents=True)

    index_file = dist_dir / "index.html"
    index_file.write_text(
        "<!doctype html><html><body>GE AppHub SPA</body></html>",
        encoding="utf-8",
    )
    asset_file = assets_dir / "app.js"
    asset_file.write_text("console.log('loaded');", encoding="utf-8")

    app = main.create_app(static_dir=dist_dir)
    client = testclient.TestClient(app)

    root_res = client.get("/")
    assert root_res.status_code == 200
    assert "GE AppHub SPA" in root_res.text

    asset_res = client.get("/assets/app.js")
    assert asset_res.status_code == 200
    assert "console.log('loaded');" in asset_res.text
