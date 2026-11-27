import { IndexContent, IndexPageLifecycle } from './IndexContent';

@Entry
@Component
struct Index {
  private readonly lifecycle: IndexPageLifecycle = new IndexPageLifecycle();

  onPageShow(): void { this.lifecycle.shown?.(); }

  onPageHide(): void { this.lifecycle.hidden?.(); }

  onBackPress(): boolean { return this.lifecycle.back?.() ?? false; }

  build() {
    Stack() {
      IndexContent({ pageLifecycle: this.lifecycle })
    }.width('100%').height('100%')
  }
}
