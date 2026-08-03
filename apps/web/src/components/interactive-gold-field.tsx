"use client";

import { useEffect, useRef } from "react";

type Particle = { x: number; y: number; vx: number; vy: number; size: number; phase: number };

export function InteractiveGoldField() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const context = canvas.getContext("2d");
    if (!context) return;

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const pointer = { x: window.innerWidth * 0.7, y: window.innerHeight * 0.34, active: false };
    let width = 0;
    let height = 0;
    let frame = 0;
    let particles: Particle[] = [];

    const resize = () => {
      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
      context.setTransform(ratio, 0, 0, ratio, 0, 0);
      const count = Math.max(42, Math.min(88, Math.round(width / 24)));
      particles = Array.from({ length: count }, () => ({
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - 0.5) * 0.26,
        vy: (Math.random() - 0.5) * 0.26,
        size: Math.random() * 1.55 + 0.45,
        phase: Math.random() * Math.PI * 2,
      }));
    };

    const movePointer = (event: PointerEvent) => {
      pointer.x = event.clientX;
      pointer.y = event.clientY;
      pointer.active = true;
    };
    const restPointer = () => { pointer.active = false; };

    const draw = (time: number) => {
      context.clearRect(0, 0, width, height);
      const horizon = context.createRadialGradient(width * 0.72, height * 0.08, 0, width * 0.72, height * 0.08, Math.max(width, height) * 0.7);
      horizon.addColorStop(0, "rgba(240, 180, 41, 0.11)");
      horizon.addColorStop(0.42, "rgba(178, 121, 17, 0.025)");
      horizon.addColorStop(1, "rgba(0, 0, 0, 0)");
      context.fillStyle = horizon;
      context.fillRect(0, 0, width, height);

      for (const particle of particles) {
        const dx = pointer.x - particle.x;
        const dy = pointer.y - particle.y;
        const distance = Math.hypot(dx, dy) || 1;
        const reach = pointer.active ? Math.max(0, 1 - distance / 250) : 0;
        const orbitX = -dy / distance;
        const orbitY = dx / distance;
        particle.vx += orbitX * reach * 0.105 + dx / distance * reach * 0.025;
        particle.vy += orbitY * reach * 0.105 + dy / distance * reach * 0.025;
        particle.vx += Math.sin(time * 0.00038 + particle.phase) * 0.006;
        particle.vy += Math.cos(time * 0.00031 + particle.phase) * 0.006;
        particle.vx *= 0.976;
        particle.vy *= 0.976;
        particle.x += particle.vx;
        particle.y += particle.vy;

        if (particle.x < -12) particle.x = width + 10;
        if (particle.x > width + 12) particle.x = -10;
        if (particle.y < -12) particle.y = height + 10;
        if (particle.y > height + 12) particle.y = -10;

        const glow = 0.34 + Math.sin(time * 0.0012 + particle.phase) * 0.18 + reach * 0.5;
        const lightTheme = document.documentElement.dataset.theme === "light";
        context.beginPath();
        context.arc(particle.x, particle.y, particle.size + reach * 1.8, 0, Math.PI * 2);
        context.shadowBlur = lightTheme ? 8 + reach * 10 : 0;
        context.shadowColor = lightTheme ? "rgba(176, 118, 15, 0.42)" : "transparent";
        context.fillStyle = lightTheme ? `rgba(154, 103, 13, ${Math.max(0.28, glow * 0.86)})` : `rgba(255, 210, 102, ${Math.max(0.12, glow)})`;
        context.fill();
        context.shadowBlur = 0;
      }
      if (!reducedMotion) frame = window.requestAnimationFrame(draw);
    };

    resize();
    window.addEventListener("resize", resize);
    window.addEventListener("pointermove", movePointer, { passive: true });
    window.addEventListener("pointerleave", restPointer, { passive: true });
    draw(performance.now());
    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener("resize", resize);
      window.removeEventListener("pointermove", movePointer);
      window.removeEventListener("pointerleave", restPointer);
    };
  }, []);

  return <div className="gold-field" aria-hidden="true"><canvas ref={canvasRef} /></div>;
}
