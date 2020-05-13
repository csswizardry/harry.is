---
layout: default
title: "All Tags"
---

<h1>{{ page.title }}</h1>

<p>
{% for tag in site.tags %}
  <a href="/{{ tag[0] }}/" class="c-lozenge">{{ tag[0] }}</a>
{% endfor %}
</p>
