#!/usr/bin/env python3
"""Son de l'animation d'ouverture (ambiance « tech »), calé sur LogoIntro.swift.

Trois petits sons numériques qui montent quand les paupières se posent, puis un verrouillage de cible
(deux notes nettes et un balayage) quand l'iris se met en place, avec un écho qui rebondit de gauche à droite
et une petite réverbération.
Produit Support/ouverture.m4a (copié dans l'app par scripts/build-app.sh).

Usage : python3 scripts/make-intro-sound.py   (demande numpy)
Si le minutage de LogoIntro.swift change, mettre à jour LIDS et IRIS (instants où chaque pièce arrive à l'œil).
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

R = 48000
LENGTH = 2.2
# Instants (secondes depuis le début de l'animation) où les paupières puis l'iris arrivent visuellement.
LIDS = [0.76, 0.88, 1.0]
IRIS = 1.19

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = np.random.default_rng(7)


def T(duration):
    return np.arange(int(duration * R)) / R


def place(buffer, start, signal, pan=0.0):
    first = int(start * R)
    count = min(len(signal), buffer.shape[1] - first)
    left, right = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    buffer[0, first:first + count] += signal[:count] * left * 1.414
    buffer[1, first:first + count] += signal[:count] * right * 1.414


def band(signal, low, high):
    spectrum = np.fft.rfft(signal)
    frequencies = np.fft.rfftfreq(len(signal), 1 / R)
    spectrum[(frequencies < low) | (frequencies > high)] = 0
    return np.fft.irfft(spectrum, len(signal))


def lowpass_sweep(signal, start_cutoff, end_cutoff):
    """Passe-bas à une pôle dont la coupure glisse de start_cutoff à end_cutoff."""
    output = np.zeros_like(signal)
    state = 0.0
    for index, sample in enumerate(signal):
        cutoff = start_cutoff * (end_cutoff / start_cutoff) ** (index / len(signal))
        state += (1 - np.exp(-2 * np.pi * cutoff / R)) * (sample - state)
        output[index] = state
    return output


def delay(buffer, seconds, feedback, mix):
    """Écho ping-pong : chaque répétition change de côté."""
    step = int(seconds * R)
    output = buffer.copy()
    for k in range(1, 6):
        shift = step * k
        if shift >= buffer.shape[1]:
            break
        gain = mix * feedback ** (k - 1)
        output[0 if k % 2 else 1, shift:] += buffer[1 if k % 2 else 0, :-shift] * gain
    return output


def reverb(buffer, decay, mix, tone=6000):
    length = int(decay * 3 * R)
    t = T(decay * 3)
    output = np.zeros_like(buffer)
    for channel in range(2):
        response = band(rng.standard_normal(length) * np.exp(-t / decay * 2.3), 200, tone)
        response /= np.sqrt(np.sum(response ** 2))
        size = buffer.shape[1] + length
        wet = np.fft.irfft(np.fft.rfft(buffer[channel], size) * np.fft.rfft(response, size))[:buffer.shape[1]]
        output[channel] = buffer[channel] * (1 - mix) + wet * mix * 1.6
    return output


def blip(frequency, duration=0.045):
    t = T(duration)
    tone = np.sin(2 * np.pi * frequency * t + 1.6 * np.sin(2 * np.pi * frequency * 2 * t) * np.exp(-t / 0.01))
    signal = tone * np.minimum(1, t / 0.001) * np.exp(-t / (duration / 3))
    return np.round(signal * 12) / 12  # léger grain numérique


buffer = np.zeros((2, int(R * LENGTH)))
for start, frequency, pan in zip(LIDS, (1320, 1568, 1760), (-0.4, 0.0, 0.4)):
    place(buffer, start, blip(frequency) * 0.6, pan)
place(buffer, IRIS, blip(2093, 0.06))
place(buffer, IRIS + 0.07, blip(2637, 0.09))
t = T(0.25)
sweep = band(rng.standard_normal(len(t)), 1500, 9000) * np.exp(-t / 0.06) * 0.25
place(buffer, IRIS + 0.07, lowpass_sweep(sweep, 9000, 800))

buffer = reverb(delay(buffer, 0.11, 0.45, 0.35), 0.4, 0.15)
buffer = np.tanh(buffer / np.max(np.abs(buffer)) * 1.2)
buffer = buffer / np.max(np.abs(buffer)) * 0.7
fade = int(0.05 * R)
buffer[:, -fade:] *= np.linspace(1, 0, fade)

with tempfile.TemporaryDirectory() as folder:
    path = os.path.join(folder, "ouverture.wav")
    with wave.open(path, "w") as file:
        file.setnchannels(2)
        file.setsampwidth(2)
        file.setframerate(R)
        file.writeframes((buffer.T * 32767).astype("<i2").tobytes())
    target = os.path.join(ROOT, "Support", "ouverture.m4a")
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "128000", path, target], check=True)
    print("Support/ouverture.m4a")
