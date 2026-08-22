import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const iosSource = resolve(process.cwd(), 'ios');

function source(filename: string): string {
  return readFileSync(resolve(iosSource, filename), 'utf8');
}

describe('iOS native view ownership', () => {
  it('clips transformed drawer content only at the drawer root', () => {
    const paperPanel = source('RNSideDrawerPanelView.mm');
    const fabricManager = source('RNSideDrawerViewManager.mm');
    const root = source('RNSideDrawerView.mm');

    expect(paperPanel).toContain('self.clipsToBounds = NO;');
    expect(fabricManager).toContain('self.clipsToBounds = NO;');
    expect(root).toContain('self.clipsToBounds = YES;');
  });
});
