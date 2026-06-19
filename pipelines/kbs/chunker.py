"""
NEXUS AI DataOps — Text chunker para KBS
Sprint 2 — P1: divide documentos em chunks para indexação no Cortex Search
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass
class Chunk:
    content: str
    chunk_index: int
    title: str
    url: str
    metadata: dict = field(default_factory=dict)


def split_by_sentences(text: str, max_chars: int) -> list[str]:
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    chunks: list[str] = []
    current = ""
    for sentence in sentences:
        if len(current) + len(sentence) + 1 <= max_chars:
            current = f"{current} {sentence}".strip() if current else sentence
        else:
            if current:
                chunks.append(current)
            current = sentence if len(sentence) <= max_chars else sentence[:max_chars]
    if current:
        chunks.append(current)
    return chunks


def chunk_document(
    content: str,
    title: str,
    url: str,
    chunk_size: int = 1500,
    chunk_overlap: int = 200,
    metadata: dict | None = None,
) -> list[Chunk]:
    if not content or not content.strip():
        return []

    content = content.strip()
    chunks: list[Chunk] = []

    if len(content) <= chunk_size:
        return [Chunk(content=content, chunk_index=0, title=title, url=url, metadata=metadata or {})]

    paragraphs = re.split(r"\n{2,}", content)
    current_chunk = ""
    chunk_index = 0

    for para in paragraphs:
        para = para.strip()
        if not para:
            continue

        if len(current_chunk) + len(para) + 2 <= chunk_size:
            current_chunk = f"{current_chunk}\n\n{para}".strip() if current_chunk else para
        else:
            if current_chunk:
                chunks.append(Chunk(
                    content=current_chunk,
                    chunk_index=chunk_index,
                    title=title,
                    url=url,
                    metadata=metadata or {},
                ))
                chunk_index += 1
                overlap_text = current_chunk[-chunk_overlap:] if len(current_chunk) > chunk_overlap else current_chunk
                current_chunk = f"{overlap_text}\n\n{para}".strip()
            else:
                if len(para) > chunk_size:
                    for sub in split_by_sentences(para, chunk_size):
                        chunks.append(Chunk(
                            content=sub,
                            chunk_index=chunk_index,
                            title=title,
                            url=url,
                            metadata=metadata or {},
                        ))
                        chunk_index += 1
                    current_chunk = ""
                else:
                    current_chunk = para

    if current_chunk:
        chunks.append(Chunk(
            content=current_chunk,
            chunk_index=chunk_index,
            title=title,
            url=url,
            metadata=metadata or {},
        ))

    return chunks


def chunk_markdown(
    markdown: str,
    title: str,
    url: str,
    chunk_size: int = 1500,
) -> list[Chunk]:
    clean = re.sub(r"```[\s\S]*?```", lambda m: m.group(0), markdown)
    clean = re.sub(r"`[^`]+`", lambda m: m.group(0), clean)
    clean = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", clean)
    clean = re.sub(r"^#{1,6}\s+", "", clean, flags=re.MULTILINE)
    clean = re.sub(r"\*\*([^*]+)\*\*", r"\1", clean)
    clean = re.sub(r"\*([^*]+)\*", r"\1", clean)
    return chunk_document(clean, title, url, chunk_size=chunk_size)
