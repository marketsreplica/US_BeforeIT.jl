#!/usr/bin/env python3
"""Browser acceptance checks for the Economy Complexity Explorer.

The Julia server and completed Standard-trace fixtures must already exist.
This harness intentionally accepts run IDs instead of creating economic data;
fixture creation remains part of the Julia API contract and can therefore be
validated independently.
"""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
from urllib.parse import urlencode, urlparse, parse_qs

from playwright.async_api import Browser, BrowserContext, Page, async_playwright


class AcceptanceFailure(AssertionError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AcceptanceFailure(message)


def state_url(base_url: str, run_id: str, **state: object) -> str:
    params: dict[str, str] = {"run": run_id}
    names = {
        "quarter": "q",
        "altitude": "altitude",
        "focus": "focus",
        "compare": "compare",
        "coverage": "coverage",
        "question": "question",
        "layers": "layers",
    }
    for key, value in state.items():
        if value is None:
            continue
        params[names.get(key, key)] = str(value)
    return f"{base_url.rstrip('/')}/explorer/?{urlencode(params)}"


async def wait_ready(page: Page, timeout: int = 30_000) -> None:
    await page.locator("#stage-loading").wait_for(state="hidden", timeout=timeout)
    await page.wait_for_function(
        """() => {
          const canvas = document.querySelector('#economy-canvas');
          const status = document.querySelector('#ledger-status');
          return canvas && canvas.width > 0 && canvas.height > 0 &&
            status && !/loading/i.test(status.textContent || '');
        }""",
        timeout=timeout,
    )
    status = (await page.locator("#ledger-status").inner_text()).strip()
    require(
        not any(label in status.lower() for label in ("load failed", "aggregate-only run")),
        f"Explorer did not reach a traced ready state: {status}",
    )
    require(await page.locator("#stage-empty").is_hidden(), "Explorer reached an empty/error state")
    await page.evaluate(
        "() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))"
    )


async def canvas_evidence(page: Page) -> dict[str, float]:
    return await page.locator("#economy-canvas").evaluate(
        """canvas => {
          const context = canvas.getContext('2d');
          const { width, height } = canvas;
          const pixels = context.getImageData(0, 0, width, height).data;
          const stride = Math.max(1, Math.floor(Math.sqrt((width * height) / 16000)));
          const colors = new Set();
          let opaque = 0;
          let samples = 0;
          for (let y = 0; y < height; y += stride) {
            for (let x = 0; x < width; x += stride) {
              const offset = (y * width + x) * 4;
              samples += 1;
              if (pixels[offset + 3] > 0) opaque += 1;
              colors.add(`${pixels[offset] >> 3}:${pixels[offset + 1] >> 3}:${pixels[offset + 2] >> 3}:${pixels[offset + 3] >> 5}`);
            }
          }
          return {
            width,
            height,
            clientWidth: canvas.clientWidth,
            clientHeight: canvas.clientHeight,
            opaqueRatio: samples ? opaque / samples : 0,
            colorBuckets: colors.size,
          };
        }"""
    )


async def require_painted_canvas(page: Page, label: str, dpr: float) -> None:
    evidence = await canvas_evidence(page)
    require(evidence["clientWidth"] > 100, f"{label}: canvas has no usable CSS width")
    require(evidence["clientHeight"] > 100, f"{label}: canvas has no usable CSS height")
    require(
        abs(evidence["width"] - evidence["clientWidth"] * dpr) <= 2,
        f"{label}: backing width does not match DPR {dpr}: {evidence}",
    )
    require(
        abs(evidence["height"] - evidence["clientHeight"] * dpr) <= 2,
        f"{label}: backing height does not match DPR {dpr}: {evidence}",
    )
    # The canvas intentionally has a CSS background and paints only the scene,
    # so sparse opening-stock views should remain mostly transparent.
    require(evidence["opaqueRatio"] > 0.001, f"{label}: no painted scene pixels were sampled: {evidence}")
    require(evidence["colorBuckets"] >= 3, f"{label}: canvas appears blank: {evidence}")


def query_value(url: str, name: str) -> str | None:
    values = parse_qs(urlparse(url).query).get(name)
    return values[0] if values else None


async def install_error_capture(page: Page) -> list[str]:
    errors: list[str] = []
    page.on("pageerror", lambda error: errors.append(f"pageerror: {error}"))
    page.on(
        "console",
        lambda message: errors.append(f"console: {message.text}")
        if message.type == "error"
        else None,
    )
    return errors


async def open_state(page: Page, url: str) -> None:
    response = await page.goto(url, wait_until="domcontentloaded")
    require(response is not None and response.ok, f"Explorer navigation failed: {url}")
    await wait_ready(page)


async def desktop_journey(
    browser: Browser,
    base_url: str,
    run_id: str,
    dpr: float,
    screenshot_dir: Path,
) -> list[str]:
    context = await browser.new_context(
        viewport={"width": 1280, "height": 800},
        device_scale_factor=dpr,
        reduced_motion="no-preference",
    )
    page = await context.new_page()
    errors = await install_error_capture(page)
    try:
        await open_state(
            page,
            state_url(base_url, run_id, quarter=1, altitude="economy"),
        )
        actual_dpr = await page.evaluate("devicePixelRatio")
        require(abs(actual_dpr - dpr) < 0.01, f"Requested DPR {dpr}, got {actual_dpr}")

        for altitude in ("economy", "sectors", "firms"):
            await page.locator(f"[data-altitude='{altitude}']").click()
            await wait_ready(page)
            require(
                query_value(page.url, "altitude") == (None if altitude == "economy" else altitude),
                f"URL did not settle on {altitude}: {page.url}",
            )
            require(
                await page.locator(f"[data-altitude='{altitude}']").get_attribute("aria-pressed") == "true",
                f"Altitude control did not settle on {altitude}",
            )
            await require_painted_canvas(page, f"{altitude} at DPR {dpr}", dpr)
            require(await page.locator("#relationship-rows tr").count() > 0, f"{altitude}: table is empty")

        # Searching a firm is valid without first visiting Firm altitude.
        await page.locator("[data-altitude='economy']").click()
        await wait_ready(page)
        firm_option = page.locator("#actor-options option[data-id^='firm:']").first
        firm_value = await firm_option.get_attribute("value")
        firm_id = await firm_option.get_attribute("data-id")
        require(bool(firm_value and firm_id), "No searchable firm was published")
        await page.locator("#actor-query").fill(firm_value or "")
        await page.locator("#actor-query").press("Enter")
        await wait_ready(page)
        require(query_value(page.url, "altitude") == "firms", "Firm search did not enter Firm altitude")
        require(query_value(page.url, "focus") == firm_id, "Firm search did not preserve exact identity")

        # Focus must survive a quarter transition.
        quarter = page.locator("#quarter-range")
        minimum = int(await quarter.get_attribute("min") or "0")
        maximum = int(await quarter.get_attribute("max") or "0")
        next_quarter = maximum if maximum != int(await quarter.input_value()) else minimum
        await quarter.evaluate(
            "(range, value) => { range.value = String(value); range.dispatchEvent(new Event('input', { bubbles: true })); }",
            next_quarter,
        )
        await wait_ready(page)
        require(query_value(page.url, "focus") == firm_id, "Quarter change discarded firm focus")

        await page.locator("[data-altitude='sectors']").click()
        await wait_ready(page)
        require((query_value(page.url, "focus") or "").startswith("sector:"), "Firm context was not preserved as sector focus")
        await page.locator("[data-altitude='firms']").click()
        await wait_ready(page)
        require((query_value(page.url, "focus") or "").startswith("firm:"), "Sector context was not preserved on return to firms")

        # A copied URL must restore the semantic state after a cold reload.
        copied_url = page.url
        await page.reload(wait_until="domcontentloaded")
        await wait_ready(page)
        require(page.url == copied_url, f"Deep-link state changed across reload: {page.url}")
        await require_painted_canvas(page, "deep-link reload", dpr)

        # The opening state has stocks and nodes but no transaction arrows.
        await open_state(
            page,
            state_url(base_url, run_id, quarter=0, altitude="economy"),
        )
        opening_copy = (await page.locator("#realization-label").inner_text()).lower()
        require("opening stock snapshot" in opening_copy, f"Quarter 0 is not labelled as an opening snapshot: {opening_copy}")
        require(await page.locator("#relationship-rows tr").count() == 0, "Quarter 0 unexpectedly exposes transaction rows")
        await require_painted_canvas(page, "opening stock snapshot", dpr)
        await open_state(
            page,
            state_url(base_url, run_id, quarter=1, altitude="economy"),
        )

        initial_play_quarter = query_value(page.url, "q")
        await page.locator("#play-toggle").click()
        require(await page.locator("#play-toggle").get_attribute("aria-label") == "Pause recorded quarters", "Playback did not start")
        await page.wait_for_function(
            "before => new URLSearchParams(location.search).get('q') !== before",
            arg=initial_play_quarter,
            timeout=5_000,
        )
        await wait_ready(page)
        await page.locator("#play-toggle").click()
        require(await page.locator("#play-toggle").get_attribute("aria-label") == "Play recorded quarters", "Playback did not pause")

        # Twenty rapid changes must settle on the last request and leave one
        # coherent table/canvas/status state.
        await page.locator("#coverage-range").evaluate(
            """range => {
              const values = [50,55,60,65,70,75,80,85,90,95,100,95,90,85,80,75,70,80,90,95];
              for (const value of values) {
                range.value = String(value);
                range.dispatchEvent(new Event('input', { bubbles: true }));
                range.dispatchEvent(new Event('change', { bubbles: true }));
              }
            }"""
        )
        await page.wait_for_function("new URLSearchParams(location.search).get('coverage') === '0.95'")
        await wait_ready(page)
        require((await page.locator("#coverage-value").inner_text()).strip() == "95%", "Rapid changes did not settle on 95%")
        require("returned" in (await page.locator("#coverage-copy").inner_text()).lower(), "Coverage disclosure is missing")

        # Layer filtering, the canonical government question, and camera
        # recovery must all leave a painted, tabularly equivalent state.
        layer = page.locator("#layer-filters [data-layer]:not([disabled])").first
        await layer.click()
        await wait_ready(page)
        require(query_value(page.url, "layers") is not None, "Layer filter was not serialized")
        require(await layer.get_attribute("aria-pressed") == "true", "Selected layer did not become active")
        require(
            await page.locator("#layer-filters [data-layer][aria-pressed='false']:not([disabled])").count() > 0,
            "Layer filtering did not suppress any other available layer",
        )
        filtered_coverage = (await page.locator("#coverage-copy").inner_text()).strip()
        require("matching relationships" in filtered_coverage.lower(), f"Filtered coverage is unclear: {filtered_coverage}")
        require(filtered_coverage in await page.locator("#canvas-summary").inner_text(), "Canvas and coverage summary did not settle atomically")
        await page.locator("#layers-all").click()
        await wait_ready(page)
        await page.locator("[data-question='government-purchases']").click()
        await wait_ready(page)
        require(query_value(page.url, "question") == "government-purchases", "Question state was not serialized")
        require(await page.locator("#relationship-rows tr").count() > 0, "Government journey returned no table rows")
        await page.locator("#direction-toggle").click()
        await wait_ready(page)
        require(query_value(page.url, "direction") == "product", "Product direction was not serialized")
        require("product direction" in (await page.locator("#direction-toggle").inner_text()).lower(), "Direction label did not update")
        for _ in range(8):
            await page.locator("#zoom-in").click()
        await page.locator("#fit-view").click()
        await page.evaluate(
            "() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))"
        )
        await require_painted_canvas(page, "camera recovery", dpr)

        # Keyboard interaction must provide a non-canvas evidence path.
        await page.locator("#economy-canvas").focus()
        await page.locator("#economy-canvas").press("n")
        await page.locator("#inspector").wait_for(state="visible")
        require((await page.locator("#inspector-title").inner_text()).strip() != "—", "Keyboard selection has no evidence title")
        await page.locator("#economy-canvas").press("Escape")
        await page.locator("#inspector").wait_for(state="hidden")
        require(query_value(page.url, "selected") is None, "Escape did not clear serialized selection")
        await page.locator("#economy-canvas").press("r")
        await page.locator("#inspector").wait_for(state="visible")
        require(await page.locator("#edge-history").is_visible(), "Keyboard relationship selection has no history panel")
        require("recorded-quarter history" in (await page.locator("#edge-history").inner_text()).lower(), "Edge history is not labelled")
        rich_deep_link = page.url
        await page.reload(wait_until="domcontentloaded")
        await wait_ready(page)
        require(page.url == rich_deep_link, "Filter/direction/question/selection state changed across deep reload")
        require(await page.locator("#inspector").is_visible(), "Serialized evidence selection was not restored")

        # The browser constraint must match the backend's strict > -90 rule.
        await page.locator("details.experiment-builder").evaluate("details => { details.open = true; }")
        await page.locator("#experiment-shock").select_option("interest_rate")
        magnitude = page.locator("#experiment-magnitude")
        await magnitude.fill("-90")
        require(not await magnitude.evaluate("input => input.checkValidity()"), "-90 pp incorrectly passes browser validation")
        await magnitude.fill("-89.75")
        require(await magnitude.evaluate("input => input.checkValidity()"), "-89.75 pp should pass browser validation")

        screenshot_dir.mkdir(parents=True, exist_ok=True)
        await page.screenshot(path=screenshot_dir / f"explorer-desktop-dpr-{dpr:g}.png", full_page=True)
        return errors
    finally:
        await context.close()


async def comparison_journey(
    browser: Browser,
    base_url: str,
    run_id: str,
    compare_id: str,
    screenshot_dir: Path,
) -> list[str]:
    context = await browser.new_context(viewport={"width": 1280, "height": 800})
    page = await context.new_page()
    errors = await install_error_capture(page)
    try:
        await open_state(
            page,
            state_url(
                base_url,
                run_id,
                quarter=1,
                altitude="sectors",
                compare=compare_id,
            ),
        )
        require(await page.locator("#comparison-panel").is_visible(), "Comparison panel is hidden")
        badge = page.locator("#comparison-panel .comparison-badge--paired")
        require(await badge.is_visible(), "The declared fixture was not certified as a paired comparison")
        require("server verified" in (await badge.get_attribute("title") or "").lower(), "Paired evidence explanation is missing")
        status = (await page.locator("#ledger-status").inner_text()).lower()
        require(status == "paired comparison", f"Comparison was not paired: {status}")
        scale = (await page.locator("#scale-badge").inner_text()).lower()
        require("scale" in scale and ("shared" in scale or "not stable" in scale), f"Scale contract is unclear: {scale}")
        require(await page.locator("#export-link").is_hidden(), "Single-run export must be hidden in comparison")
        caption = (await page.locator("#table-caption").text_content() or "").lower()
        require("comparison export is not available" in caption, f"Comparison table caption is misleading: {caption}")
        require("export includes every server-matching" not in caption, f"Comparison caption promises a hidden export: {caption}")
        await page.locator("#economy-canvas").focus()
        await page.locator("#economy-canvas").press("n")
        await page.locator("#inspector").wait_for(state="visible")
        require(await page.locator("#comparison-panel").is_hidden(), "Comparison summary should yield to the selected receipt")
        reconciliation = (await page.locator("#node-reconciliation").inner_text()).lower()
        metrics = (await page.locator("#inspector-metrics").inner_text()).lower()
        require("stock–flow proof unavailable" in reconciliation, "Missing comparison node-evidence limitation")
        require("not provided by the comparison endpoint" in metrics, "Unpaired node metrics were not explicitly suppressed")
        await page.locator("#economy-canvas").press("r")
        receipt = (await page.locator("#inspector-metrics").inner_text()).lower()
        require(all(label in receipt for label in ("run a", "run b", "delta b minus a")), f"Comparison receipt lacks A/B/delta values: {receipt}")
        await require_painted_canvas(page, "paired comparison", 1)
        screenshot_dir.mkdir(parents=True, exist_ok=True)
        await page.screenshot(path=screenshot_dir / "explorer-comparison-receipt.png", full_page=True)
        await page.locator("#economy-canvas").press("Escape")
        await page.locator("#inspector").wait_for(state="hidden")
        require(await page.locator("#comparison-panel").is_visible(), "Comparison summary did not return after closing the receipt")
        require(await page.locator("#tooltip").is_hidden(), "Escape did not clear the keyboard hover tooltip")
        await page.screenshot(path=screenshot_dir / "explorer-comparison.png", full_page=True)
        return errors
    finally:
        await context.close()


async def mobile_reduced_motion_journey(
    browser: Browser,
    base_url: str,
    run_id: str,
    screenshot_dir: Path,
) -> list[str]:
    context: BrowserContext = await browser.new_context(
        viewport={"width": 390, "height": 844},
        device_scale_factor=2,
        reduced_motion="reduce",
        is_mobile=True,
        has_touch=True,
    )
    page = await context.new_page()
    errors = await install_error_capture(page)
    try:
        await open_state(page, state_url(base_url, run_id, quarter=1, altitude="economy"))
        require(await page.evaluate("matchMedia('(prefers-reduced-motion: reduce)').matches"), "Reduced motion was not applied")
        overflow = await page.evaluate("document.documentElement.scrollWidth - document.documentElement.clientWidth")
        require(overflow <= 2, f"Mobile page has {overflow}px horizontal overflow")
        await require_painted_canvas(page, "mobile reduced-motion", 2)
        screenshot_dir.mkdir(parents=True, exist_ok=True)
        await page.screenshot(path=screenshot_dir / "explorer-mobile-reduced-motion.png", full_page=True)
        return errors
    finally:
        await context.close()


async def run(args: argparse.Namespace) -> None:
    screenshot_dir = Path(args.screenshot_dir).expanduser().resolve()
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=not args.headed)
        try:
            results = [
                ("desktop DPR 1", await desktop_journey(browser, args.base_url, args.run, 1, screenshot_dir)),
                ("desktop DPR 2", await desktop_journey(browser, args.base_url, args.run, 2, screenshot_dir)),
                ("mobile reduced motion", await mobile_reduced_motion_journey(browser, args.base_url, args.run, screenshot_dir)),
            ]
            if args.compare:
                results.append(
                    (
                        "paired comparison",
                        await comparison_journey(browser, args.base_url, args.run, args.compare, screenshot_dir),
                    )
                )
        finally:
            await browser.close()

    browser_errors = [f"{journey}: {error}" for journey, errors in results for error in errors]
    require(not browser_errors, "Browser errors:\n" + "\n".join(browser_errors))
    print(
        json.dumps(
            {
                "status": "passed",
                "journeys": [name for name, _ in results],
                "screenshots": str(screenshot_dir),
            },
            indent=2,
        )
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8081")
    parser.add_argument("--run", required=True, help="Completed Standard-trace baseline run ID")
    parser.add_argument("--compare", help="Optional completed paired treatment run ID")
    parser.add_argument("--screenshot-dir", default="/private/tmp/beforeit-explorer-acceptance")
    parser.add_argument("--headed", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    asyncio.run(run(parse_args()))
