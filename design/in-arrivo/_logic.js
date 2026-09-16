class Component extends DCLogic {
  // The page's colours the way Flavor derives them: a faint tint of Main for
  // the ground, a deeper one for cards. Same formulas as Flavor.ground /
  // Flavor.surface, so a Flavor tweak restains the whole preview.
  hsb(hex) {
    const n = parseInt(String(hex).replace('#', ''), 16);
    const r = ((n >> 16) & 255) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
    let h = 0;
    if (d) {
      if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
      else if (max === g) h = ((b - r) / d + 2) / 6;
      else h = ((r - g) / d + 4) / 6;
    }
    return [h, max ? d / max : 0, max];
  }
  hex(h, s, v) {
    const f = (n) => {
      const k = (n + h * 6) % 6;
      return Math.round(255 * (v - v * s * Math.max(0, Math.min(k, 4 - k, 1))));
    };
    return '#' + [f(5), f(3), f(1)].map((c) => c.toString(16).padStart(2, '0')).join('').toUpperCase();
  }
  page() {
    const main = this.props.flavor ?? '#0F3D6E';
    const [h, s] = this.hsb(main);
    const ground = this.hex(h, Math.min(s * 0.06, 0.06), 0.98);
    const card = this.hex(h, Math.min(s * 0.11, 0.1), 0.945);
    const surface = this.hex(h, Math.min(s * 0.16, 0.14), 0.9);
    const line = this.hex(h, Math.min(s * 0.2, 0.18), 0.82);
    const paper = this.props.paper ?? 'Puntinata';
    const dot = this.hex(h, Math.min(s * 0.3, 0.3), 0.78);
    const papers = {
      Liscia: { image: 'none', size: 'auto' },
      Puntinata: { image: 'radial-gradient(' + dot + ' 1.1px, transparent 1.2px)', size: '12px 12px' },
      Millimetrata: {
        image: 'linear-gradient(' + dot + ' 0.6px, transparent 0.6px), linear-gradient(90deg, ' + dot + ' 0.6px, transparent 0.6px)',
        size: '9px 9px',
      },
    };
    const chosen = papers[paper] ?? papers.Puntinata;
    return { accent: main, ground, card, surface, line, paperImage: chosen.image, paperSize: chosen.size };
  }
  renderVals() {
    return this.page();
  }
}
