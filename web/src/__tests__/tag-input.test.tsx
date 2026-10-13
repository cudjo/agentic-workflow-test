/**
 * tag-input.test.tsx — поле тегов редактора (DESIGN §2.5): ввод по Enter/запятой,
 * чипы с удалением, лимиты 20/50, дубликаты и пустые не добавляются, datalist.
 */
import { useState } from 'react';
import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MAX_TAG_LENGTH, TagInput } from '../components/TagInput';

function Harness({ initial = [] }: { initial?: string[] }) {
  const [tags, setTags] = useState<string[]>(initial);
  return (
    <TagInput tags={tags} suggestions={['работа', 'планы']} onChange={setTags} />
  );
}

function chipNames(): string[] {
  return screen
    .queryAllByRole('button', { name: /^Убрать тег/ })
    .map((button) => button.getAttribute('aria-label') ?? '');
}

describe('поле тегов', () => {
  it('добавляет тег по Enter и по запятой', async () => {
    const user = userEvent.setup();
    render(<Harness />);
    const input = screen.getByLabelText('Теги');

    await user.type(input, 'работа{Enter}');
    expect(screen.getByRole('button', { name: 'Убрать тег «работа»' })).toBeInTheDocument();

    await user.type(input, 'планы,');
    expect(screen.getByRole('button', { name: 'Убрать тег «планы»' })).toBeInTheDocument();
    expect(input).toHaveValue('');
  });

  it('пустой и пробельный тег не добавляется', async () => {
    const user = userEvent.setup();
    render(<Harness />);
    const input = screen.getByLabelText('Теги');

    await user.type(input, '   {Enter}');
    expect(chipNames()).toHaveLength(0);
  });

  it('дубликат без учёта регистра не добавляется', async () => {
    const user = userEvent.setup();
    render(<Harness initial={['Работа']} />);
    const input = screen.getByLabelText('Теги');

    await user.type(input, 'работа{Enter}');
    expect(chipNames()).toEqual(['Убрать тег «Работа»']);
  });

  it('тег длиннее 50 символов отклоняется с сообщением', async () => {
    const user = userEvent.setup();
    render(<Harness />);
    const input = screen.getByLabelText('Теги');

    await user.type(input, `${'a'.repeat(MAX_TAG_LENGTH + 1)}{Enter}`);
    expect(await screen.findByText('Тег длиннее 50 символов')).toBeInTheDocument();
    expect(chipNames()).toHaveLength(0);
    expect(input).toHaveAttribute('aria-invalid', 'true');
  });

  it('более 20 тегов отклоняется с сообщением', async () => {
    const user = userEvent.setup();
    render(<Harness />);
    const input = screen.getByLabelText('Теги');

    for (let i = 0; i < 20; i += 1) {
      await user.type(input, `${String.fromCharCode(97 + i)}{Enter}`);
    }
    expect(chipNames()).toHaveLength(20);

    await user.type(input, 'z{Enter}');
    expect(await screen.findByText('Не больше 20 тегов')).toBeInTheDocument();
    expect(chipNames()).toHaveLength(20);
  });

  it('чип удаляется кнопкой с контекстным aria-label', async () => {
    const user = userEvent.setup();
    render(<Harness initial={['работа', 'планы']} />);

    await user.click(screen.getByRole('button', { name: 'Убрать тег «работа»' }));
    expect(screen.queryByRole('button', { name: 'Убрать тег «работа»' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Убрать тег «планы»' })).toBeInTheDocument();
  });

  it('подсказки приходят из datalist', () => {
    render(<Harness />);
    const options = Array.from(document.querySelectorAll('datalist option')).map(
      (option) => (option as HTMLOptionElement).value,
    );
    expect(options).toEqual(['работа', 'планы']);
  });
});
