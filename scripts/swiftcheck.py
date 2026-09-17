#!/usr/bin/env python3
"""Controllo strutturale di file Swift, senza compilatore.

Non è un compilatore: non conosce i tipi, non sa se un'API esiste, non vede
l'isolamento degli attori. Fa una cosa sola e la fa davvero: legge il file
carattere per carattere sapendo distinguere codice, commenti (anche annidati),
stringhe normali, stringhe multilinea, stringhe grezze con #, e interpolazioni
\\(...). Poi verifica che le parentesi si chiudano e che nessuna stringa resti
aperta — cioè gli errori che si fanno scrivendo alla cieca.
"""
import sys

def check(path):
    src = open(path, encoding='utf-8').read()
    i, n = 0, len(src)
    line = 1
    stack = []            # parentesi aperte: (carattere, riga)
    errs = []
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1; i += 1; continue
        # commento di riga
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        # commento a blocco, annidabile in Swift
        if src.startswith('/*', i):
            depth, i = 1, i + 2
            while i < n and depth:
                if src.startswith('/*', i): depth += 1; i += 2
                elif src.startswith('*/', i): depth -= 1; i += 2
                else:
                    if src[i] == '\n': line += 1
                    i += 1
            if depth: errs.append(f'{path}: commento a blocco mai chiuso')
            continue
        # stringa grezza: cancelletti prima delle virgolette
        hashes = 0
        j = i
        while j < n and src[j] == '#': hashes += 1; j += 1
        if j < n and src[j] == '"':
            closing = '"' * (3 if src.startswith('"""', j) else 1) + '#' * hashes
            multi = src.startswith('"""', j)
            k = j + (3 if multi else 1)
            start_line = line
            while k < n:
                if src[k] == '\n':
                    line += 1
                    if not multi and hashes == 0:
                        errs.append(f'{path}:{start_line}: stringa a riga singola mai chiusa')
                        break
                    k += 1; continue
                if src[k] == '\\' and (hashes == 0 or src.startswith('\\' + '#' * hashes, k)):
                    esc = 1 + hashes
                    # interpolazione: salta il gruppo bilanciato
                    if k + esc < n and src[k + esc] == '(':
                        d, k = 0, k + esc
                        while k < n:
                            if src[k] == '(': d += 1
                            elif src[k] == ')':
                                d -= 1
                                if d == 0: k += 1; break
                            elif src[k] == '\n': line += 1
                            k += 1
                        continue
                    k += esc + 1; continue
                if src.startswith(closing, k):
                    k += len(closing); break
                k += 1
            else:
                errs.append(f'{path}:{start_line}: stringa mai chiusa')
            i = k
            continue
        if hashes:
            i = j; continue
        if c in '([{':
            stack.append((c, line)); i += 1; continue
        if c in ')]}':
            want = {')': '(', ']': '[', '}': '{'}[c]
            if not stack:
                errs.append(f'{path}:{line}: «{c}» senza apertura')
            elif stack[-1][0] != want:
                o, ol = stack.pop()
                errs.append(f'{path}:{line}: «{c}» chiude «{o}» aperta a riga {ol}')
            else:
                stack.pop()
            i += 1; continue
        i += 1
    for o, ol in stack:
        errs.append(f'{path}:{ol}: «{o}» mai chiusa')
    return errs

bad = 0
for p in sys.argv[1:]:
    for e in check(p):
        print(e); bad = 1
sys.exit(bad)
