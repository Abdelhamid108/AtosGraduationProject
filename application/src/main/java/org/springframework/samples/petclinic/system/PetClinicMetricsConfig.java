/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.springframework.samples.petclinic.system;

import io.micrometer.core.aop.TimedAspect;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Configuration for application-level observability, Micrometer meters, and timers.
 */
@Configuration(proxyBeanMethods = false)
public class PetClinicMetricsConfig {

	@Bean
	public TimedAspect timedAspect(MeterRegistry registry) {
		return new TimedAspect(registry);
	}

	@Bean
	public Counter ownerCreationCounter(MeterRegistry registry) {
		return Counter.builder("petclinic.owners.created.total")
			.description("Total number of owner registrations")
			.register(registry);
	}

	@Bean
	public Counter petCreationCounter(MeterRegistry registry) {
		return Counter.builder("petclinic.pets.created.total")
			.description("Total number of registered pets")
			.register(registry);
	}

	@Bean
	public Counter visitCreationCounter(MeterRegistry registry) {
		return Counter.builder("petclinic.visits.created.total")
			.description("Total number of scheduled clinic visits")
			.register(registry);
	}

}